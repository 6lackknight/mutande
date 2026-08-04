//! Auth0 Authorization Code + PKCE with loopback redirect for native Mac login.

use std::collections::HashMap;
use std::time::Duration;

use anyhow::{bail, Context, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use rand::RngCore;
use sha2::{Digest, Sha256};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::sync::oneshot;

use crate::hub_client::{
    auth0_authorize_endpoint, auth0_token_endpoint, Auth0TokenResponse,
};

#[derive(Clone, Debug)]
pub struct Auth0NativeConfig {
    pub domain: String,
    pub client_id: String,
    pub audience: String,
    /// When false, skip `open` / browser launch (tests).
    pub open_browser: bool,
}

#[derive(Clone, Debug)]
pub struct Auth0Tokens {
    pub access_token: String,
    pub refresh_token: Option<String>,
}

/// Fixed loopback port for Auth0 Allowed Callback URLs.
/// Register exactly: `http://127.0.0.1:8732/callback`
pub const AUTH0_LOOPBACK_PORT: u16 = 8732;

/// How long the daemon keeps the loopback listener open awaiting the browser callback.
const AUTH0_CALLBACK_TIMEOUT: Duration = Duration::from_secs(300);

/// Run Auth0 login via loopback `http://127.0.0.1:8732/callback`.
///
/// Order is intentional: bind → log ready → spawn accept loop → open browser → wait.
/// Ephemeral ports are not used (Auth0 only allows the registered callback URL).
pub async fn login_with_loopback(cfg: &Auth0NativeConfig) -> Result<Auth0Tokens> {
    let listener = TcpListener::bind(("127.0.0.1", AUTH0_LOOPBACK_PORT))
        .await
        .with_context(|| {
            format!(
                "cannot bind Auth0 loopback http://127.0.0.1:{AUTH0_LOOPBACK_PORT}/callback — \
                 port {AUTH0_LOOPBACK_PORT} is in use (another sign-in may be in progress). \
                 Free the port and retry; the browser is not opened until bind succeeds."
            )
        })?;
    let redirect_uri = format!("http://127.0.0.1:{AUTH0_LOOPBACK_PORT}/callback");
    // Confirm the OS assigned the port we asked for before advertising it to Auth0.
    let bound = listener.local_addr().context("Auth0 loopback local_addr")?;
    if bound.port() != AUTH0_LOOPBACK_PORT {
        bail!(
            "Auth0 loopback bound unexpected port {} (wanted {AUTH0_LOOPBACK_PORT})",
            bound.port()
        );
    }
    tracing::info!(
        %redirect_uri,
        port = AUTH0_LOOPBACK_PORT,
        "Auth0 loopback listener ready"
    );

    let (verifier, challenge) = pkce_pair()?;
    let state = random_urlsafe(16);

    let authorize = format!(
        "{}?response_type=code&client_id={}&redirect_uri={}&scope={}&audience={}&state={}&code_challenge={}&code_challenge_method=S256",
        auth0_authorize_endpoint(&cfg.domain),
        percent_encode(&cfg.client_id),
        percent_encode(&redirect_uri),
        percent_encode("openid profile email offline_access"),
        percent_encode(&cfg.audience),
        percent_encode(&state),
        percent_encode(&challenge),
    );

    // Accept loop runs independently of the HTTP RPC connection so a Flutter
    // client disconnect cannot drop the socket before the browser callback.
    let (tx, rx) = oneshot::channel::<Result<(String, String)>>();
    let accept_task = tokio::spawn(async move {
        let result = accept_callback(listener, &state).await;
        let _ = tx.send(result);
    });

    if cfg.open_browser {
        tracing::info!(port = AUTH0_LOOPBACK_PORT, "Auth0 opening system browser");
        open_url(&authorize)?;
    } else {
        tracing::info!(%authorize, "Auth0 authorize URL (open_browser=false)");
    }

    let timed = tokio::time::timeout(AUTH0_CALLBACK_TIMEOUT, rx).await;
    if timed.is_err() {
        accept_task.abort();
        bail!(
            "Auth0 login timed out ({} minutes) — loopback was listening on {redirect_uri}",
            AUTH0_CALLBACK_TIMEOUT.as_secs() / 60
        );
    }
    let (code, _returned_state) = timed
        .expect("timeout checked")
        .context("Auth0 callback channel closed")??;
    // Intentionally never log `code` (one-time OAuth secret).
    tracing::info!("Auth0 authorization code received — exchanging tokens");

    let tokens = exchange_code(
        &cfg.domain,
        &cfg.client_id,
        &redirect_uri,
        &code,
        &verifier,
    )
    .await?;

    Ok(Auth0Tokens {
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
    })
}

/// Accept until a real `/callback` arrives. Ignores favicon/empty/noise probes so
/// a single stray connection cannot tear down the listener before Auth0 redirects.
async fn accept_callback(listener: TcpListener, expected_state: &str) -> Result<(String, String)> {
    loop {
        let (mut socket, peer) = listener.accept().await.context("accept Auth0 callback")?;
        tracing::debug!(?peer, "Auth0 loopback connection");

        let mut buf = vec![0u8; 8192];
        let n = match socket.read(&mut buf).await {
            Ok(0) => {
                tracing::debug!("Auth0 loopback empty connection — ignoring");
                continue;
            }
            Ok(n) => n,
            Err(err) => {
                tracing::debug!(error = %err, "Auth0 loopback read failed — ignoring");
                continue;
            }
        };
        let req = String::from_utf8_lossy(&buf[..n]);
        let first_line = req.lines().next().unwrap_or_default();
        // GET /callback?code=...&state=... HTTP/1.1
        let Some(path) = first_line.split_whitespace().nth(1) else {
            tracing::debug!("Auth0 loopback malformed request line — ignoring");
            continue;
        };
        let (path_only, query) = path.split_once('?').unwrap_or((path, ""));
        if path_only != "/callback" {
            tracing::debug!(path = %path_only, "Auth0 loopback ignoring non-callback path");
            let body = html_page(
                CallbackKind::Error,
                "Not found",
                "This page is only used for mutande sign-in.",
                Some("Return to the app and try Sign in again."),
                None,
            );
            let _ = write_http_response(&mut socket, 404, &body).await;
            continue;
        }

        let params = parse_query(query);
        if let Some(err) = params.get("error") {
            let desc = params
                .get("error_description")
                .map(String::as_str)
                .unwrap_or("");
            let detail = format!("{err} {desc}").trim().to_string();
            let body = html_page(
                CallbackKind::Error,
                "Sign-in failed",
                "Something went wrong while signing in.",
                Some("You can close this window and try again from the app."),
                if detail.is_empty() {
                    None
                } else {
                    Some(detail.as_str())
                },
            );
            write_http_response(&mut socket, 400, &body).await?;
            bail!("Auth0 error: {err} {desc}");
        }
        let code = match params.get("code") {
            Some(c) if !c.is_empty() => c.clone(),
            _ => {
                let body = html_page(
                    CallbackKind::Error,
                    "Sign-in failed",
                    "Missing authorization code.",
                    Some("You can close this window and try again from the app."),
                    None,
                );
                let _ = write_http_response(&mut socket, 400, &body).await;
                continue;
            }
        };
        let state = match params.get("state") {
            Some(s) if !s.is_empty() => s.clone(),
            _ => {
                let body = html_page(
                    CallbackKind::Error,
                    "Sign-in failed",
                    "Missing sign-in state.",
                    Some("You can close this window and try again from the app."),
                    None,
                );
                let _ = write_http_response(&mut socket, 400, &body).await;
                continue;
            }
        };
        if state != expected_state {
            let body = html_page(
                CallbackKind::Error,
                "Sign-in failed",
                "This sign-in link is no longer valid.",
                Some("You can close this window and try again from the app."),
                Some("State mismatch."),
            );
            write_http_response(&mut socket, 400, &body).await?;
            bail!("Auth0 state mismatch");
        }
        let body = html_page(
            CallbackKind::Success,
            "You're signed in",
            "mutande signed you in.",
            Some("You can close this window and return to the app."),
            None,
        );
        write_http_response(&mut socket, 200, &body).await?;
        return Ok((code, state));
    }
}

async fn write_http_response(
    socket: &mut tokio::net::TcpStream,
    status: u16,
    body: &str,
) -> Result<()> {
    let reason = match status {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        _ => "Error",
    };
    let resp = format!(
        "HTTP/1.1 {status} {reason}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    socket.write_all(resp.as_bytes()).await?;
    socket.flush().await?;
    Ok(())
}

#[derive(Clone, Copy)]
enum CallbackKind {
    Success,
    Error,
}

fn html_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(c),
        }
    }
    out
}

/// Self-contained loopback interstitial (no external assets — must work offline).
fn html_page(
    kind: CallbackKind,
    title: &str,
    message: &str,
    secondary: Option<&str>,
    detail: Option<&str>,
) -> String {
    let title_e = html_escape(title);
    let message_e = html_escape(message);
    let secondary_html = secondary
        .map(|s| format!("<p class=\"secondary\">{}</p>", html_escape(s)))
        .unwrap_or_default();
    let detail_html = detail
        .map(|s| format!("<p class=\"detail\">{}</p>", html_escape(s)))
        .unwrap_or_default();
    let (status_class, status_label, auto_close_ms) = match kind {
        CallbackKind::Success => ("ok", "Signed in", 2800u32),
        CallbackKind::Error => ("err", "Could not finish", 0u32),
    };
    let auto_close_script = if auto_close_ms > 0 {
        format!(
            r#"<script>
(function(){{
  var ms={auto_close_ms};
  window.setTimeout(function(){{
    try {{ window.close(); }} catch (e) {{}}
  }}, ms);
}})();
</script>"#
        )
    } else {
        String::new()
    };

    format!(
        r#"<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title_e} · mutande</title>
<style>
  :root {{
    --stone-0: #f2f0ed;
    --stone-1: #e6e3df;
    --stone-2: #cfcbc5;
    --slate: #5c5a57;
    --charcoal: #2a2826;
    --ink: #1c1b1a;
    --ok: #3d6b56;
    --err: #8a5348;
    --mark-bg: #141312;
    --mark-fg: #f7f5f2;
  }}
  * {{ box-sizing: border-box; }}
  html, body {{ height: 100%; margin: 0; }}
  body {{
    min-height: 100%;
    display: grid;
    place-items: center;
    padding: 2rem 1.25rem;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI",
      system-ui, sans-serif;
    color: var(--charcoal);
    background:
      radial-gradient(1200px 600px at 50% -10%, #faf8f5 0%, transparent 55%),
      linear-gradient(165deg, var(--stone-0) 0%, var(--stone-1) 48%, #ddd9d3 100%);
    -webkit-font-smoothing: antialiased;
  }}
  body::before {{
    content: "";
    position: fixed;
    inset: 0;
    pointer-events: none;
    opacity: 0.035;
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
  }}
  main {{
    position: relative;
    width: min(22rem, 100%);
    text-align: center;
    animation: rise 420ms cubic-bezier(0.16, 1, 0.3, 1) both;
  }}
  .mark {{
    width: 3rem;
    height: 3rem;
    margin: 0 auto 1.25rem;
    border-radius: 0.7rem;
    background: var(--mark-bg);
    color: var(--mark-fg);
    display: grid;
    place-items: center;
    box-shadow: 0 1px 0 rgba(255,255,255,0.35) inset, 0 10px 28px rgba(28,27,26,0.12);
  }}
  .mark span {{
    font-family: "SF Pro Rounded", "Avenir Next", -apple-system, sans-serif;
    font-size: 1.05rem;
    font-weight: 700;
    letter-spacing: -0.06em;
    line-height: 1;
    transform: translateY(0.5px);
  }}
  .brand {{
    margin: 0 0 1.5rem;
    font-size: 1.375rem;
    font-weight: 600;
    letter-spacing: -0.03em;
    color: var(--ink);
  }}
  .status {{
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    margin: 0 0 0.75rem;
    padding: 0.2rem 0.55rem;
    border-radius: 999px;
    font-size: 0.6875rem;
    font-weight: 600;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    background: rgba(42, 40, 38, 0.06);
    color: var(--slate);
  }}
  .status.ok {{ color: var(--ok); background: rgba(61, 107, 86, 0.1); }}
  .status.err {{ color: var(--err); background: rgba(138, 83, 72, 0.1); }}
  .status i {{
    width: 0.4rem;
    height: 0.4rem;
    border-radius: 50%;
    background: currentColor;
    opacity: 0.85;
  }}
  h1 {{
    margin: 0 0 0.5rem;
    font-size: 1.125rem;
    font-weight: 600;
    letter-spacing: -0.02em;
    color: var(--ink);
  }}
  .message {{
    margin: 0;
    font-size: 0.9375rem;
    line-height: 1.45;
    color: var(--charcoal);
  }}
  .secondary {{
    margin: 0.65rem 0 0;
    font-size: 0.8125rem;
    line-height: 1.45;
    color: var(--slate);
  }}
  .detail {{
    margin: 1rem 0 0;
    padding: 0.65rem 0.75rem;
    border-radius: 0.55rem;
    background: rgba(28, 27, 26, 0.04);
    border: 1px solid rgba(28, 27, 26, 0.06);
    font-size: 0.75rem;
    line-height: 1.4;
    color: var(--slate);
    word-break: break-word;
    text-align: left;
  }}
  @keyframes rise {{
    from {{ opacity: 0; transform: translateY(6px); }}
    to {{ opacity: 1; transform: translateY(0); }}
  }}
  @media (prefers-reduced-motion: reduce) {{
    main {{ animation: none; }}
  }}
</style>
</head>
<body>
  <main>
    <div class="mark" aria-hidden="true"><span>mt</span></div>
    <p class="brand">mutande</p>
    <p class="status {status_class}"><i></i>{status_label}</p>
    <h1>{title_e}</h1>
    <p class="message">{message_e}</p>
    {secondary_html}
    {detail_html}
  </main>
  {auto_close_script}
</body>
</html>"#
    )
}

async fn exchange_code(
    domain: &str,
    client_id: &str,
    redirect_uri: &str,
    code: &str,
    code_verifier: &str,
) -> Result<Auth0TokenResponse> {
    let url = auth0_token_endpoint(domain);
    let body = serde_json::json!({
        "grant_type": "authorization_code",
        "client_id": client_id,
        "code": code,
        "redirect_uri": redirect_uri,
        "code_verifier": code_verifier,
    });
    let client = reqwest::Client::new();
    let resp = client
        .post(&url)
        .json(&body)
        .send()
        .await
        .context("Auth0 code exchange")?;
    if resp.status().is_success() {
        resp.json().await.context("decode Auth0 token response")
    } else {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        bail!("Auth0 token exchange failed {status}: {text}");
    }
}

fn pkce_pair() -> Result<(String, String)> {
    let verifier = random_urlsafe(32);
    let mut hasher = Sha256::new();
    hasher.update(verifier.as_bytes());
    let challenge = URL_SAFE_NO_PAD.encode(hasher.finalize());
    Ok((verifier, challenge))
}

fn random_urlsafe(nbytes: usize) -> String {
    let mut buf = vec![0u8; nbytes];
    rand::thread_rng().fill_bytes(&mut buf);
    URL_SAFE_NO_PAD.encode(buf)
}

fn parse_query(query: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for part in query.split('&') {
        if part.is_empty() {
            continue;
        }
        let (k, v) = part.split_once('=').unwrap_or((part, ""));
        map.insert(percent_decode(k), percent_decode(v));
    }
    map
}

fn percent_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 3);
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char);
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(h), Some(l)) = (from_hex(bytes[i + 1]), from_hex(bytes[i + 2])) {
                out.push((h << 4) | l);
                i += 3;
                continue;
            }
        }
        if bytes[i] == b'+' {
            out.push(b' ');
        } else {
            out.push(bytes[i]);
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn from_hex(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

fn open_url(url: &str) -> Result<()> {
    #[cfg(target_os = "macos")]
    {
        // Do not wait — `open` returning must not gate the accept loop.
        std::process::Command::new("open")
            .arg(url)
            .spawn()
            .context("open Auth0 authorize URL")?;
        return Ok(());
    }
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("cmd")
            .args(["/C", "start", "", url])
            .spawn()
            .context("open Auth0 authorize URL")?;
        return Ok(());
    }
    #[cfg(all(not(target_os = "macos"), not(target_os = "windows")))]
    {
        tracing::warn!(%url, "open browser not implemented on this OS — open URL manually");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pkce_challenge_is_s256() {
        let (verifier, challenge) = pkce_pair().unwrap();
        assert!(!verifier.is_empty());
        let mut hasher = Sha256::new();
        hasher.update(verifier.as_bytes());
        let expected = URL_SAFE_NO_PAD.encode(hasher.finalize());
        assert_eq!(challenge, expected);
    }

    #[test]
    fn percent_roundtrip_basic() {
        let s = "openid profile email";
        let enc = percent_encode(s);
        assert_eq!(percent_decode(&enc), s);
    }

    #[test]
    fn html_escape_entities() {
        assert_eq!(html_escape(r#"a<b>&"'"#), "a&lt;b&gt;&amp;&quot;&#39;");
    }

    #[test]
    fn success_page_is_self_contained() {
        let html = html_page(
            CallbackKind::Success,
            "You're signed in",
            "mutande signed you in.",
            Some("You can close this window and return to the app."),
            None,
        );
        assert!(html.contains("mutande"));
        assert!(html.contains("window.close"));
        assert!(!html.contains("<link "));
        assert!(!html.contains("src=\"http"));
        assert!(html.contains("prefers-reduced-motion"));
    }

    #[test]
    fn error_page_escapes_detail() {
        let html = html_page(
            CallbackKind::Error,
            "Sign-in failed",
            "Something went wrong while signing in.",
            Some("You can close this window."),
            Some(r#"access_denied <script>alert(1)</script>"#),
        );
        assert!(html.contains("&lt;script&gt;"));
        assert!(!html.contains("<script>alert"));
        assert!(!html.contains("window.close"));
    }

    #[tokio::test]
    async fn accept_callback_ignores_noise_then_succeeds() {
        use tokio::io::AsyncWriteExt;
        use tokio::net::TcpStream;

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let state = "test-state-xyz".to_string();
        let expected = state.clone();
        let task = tokio::spawn(async move { accept_callback(listener, &expected).await });

        // Favicon / noise must not tear down the listener.
        {
            let mut c = TcpStream::connect(addr).await.unwrap();
            c.write_all(b"GET /favicon.ico HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
                .await
                .unwrap();
        }
        {
            let _c = TcpStream::connect(addr).await.unwrap();
            // Drop without sending — empty read path.
        }
        tokio::time::sleep(Duration::from_millis(30)).await;

        {
            let mut c = TcpStream::connect(addr).await.unwrap();
            let req = format!(
                "GET /callback?code=one-time-code&state={state} HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
            );
            c.write_all(req.as_bytes()).await.unwrap();
            let mut buf = vec![0u8; 2048];
            let n = c.read(&mut buf).await.unwrap();
            let resp = String::from_utf8_lossy(&buf[..n]);
            assert!(resp.starts_with("HTTP/1.1 200"), "{resp}");
        }

        let (code, got_state) = task.await.unwrap().unwrap();
        assert_eq!(code, "one-time-code");
        assert_eq!(got_state, state);
    }

    #[tokio::test]
    async fn login_binds_fixed_port_before_waiting() {
        // If 8732 is free, bind succeeds and open_browser=false never opens Safari.
        // Skip when the preferred port is already taken (another login in progress).
        let probe = TcpListener::bind(("127.0.0.1", AUTH0_LOOPBACK_PORT)).await;
        let Ok(probe) = probe else {
            return;
        };
        drop(probe);

        let cfg = Auth0NativeConfig {
            domain: "example.auth0.com".into(),
            client_id: "test-client".into(),
            audience: "https://hub.mutande.app".into(),
            open_browser: false,
        };
        let login = tokio::spawn(async move { login_with_loopback(&cfg).await });
        // Listener must be up quickly after spawn.
        let mut listening = false;
        for _ in 0..50 {
            tokio::time::sleep(Duration::from_millis(20)).await;
            if tokio::net::TcpStream::connect(("127.0.0.1", AUTH0_LOOPBACK_PORT))
                .await
                .is_ok()
            {
                listening = true;
                break;
            }
        }
        assert!(listening, "loopback should listen on {AUTH0_LOOPBACK_PORT} before browser");
        login.abort();
    }
}
