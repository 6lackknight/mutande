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

/// Preferred loopback port for Auth0 Allowed Callback URLs.
/// Register: `http://127.0.0.1:8732/callback`
pub const AUTH0_LOOPBACK_PORT: u16 = 8732;

/// Run Auth0 login via loopback `http://127.0.0.1:8732/callback` (falls back to ephemeral).
pub async fn login_with_loopback(cfg: &Auth0NativeConfig) -> Result<Auth0Tokens> {
    let listener = match TcpListener::bind(("127.0.0.1", AUTH0_LOOPBACK_PORT)).await {
        Ok(l) => l,
        Err(err) => {
            tracing::warn!(
                port = AUTH0_LOOPBACK_PORT,
                error = %err,
                "Auth0 preferred loopback busy — using ephemeral port"
            );
            TcpListener::bind("127.0.0.1:0")
                .await
                .context("bind Auth0 loopback")?
        }
    };
    let port = listener.local_addr()?.port();
    let redirect_uri = format!("http://127.0.0.1:{port}/callback");
    if port != AUTH0_LOOPBACK_PORT {
        tracing::warn!(
            %redirect_uri,
            "Register this exact callback URL in Auth0 Native app settings"
        );
    }

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

    let (tx, rx) = oneshot::channel::<Result<(String, String)>>();
    tokio::spawn(async move {
        let result = accept_callback(listener, &state).await;
        let _ = tx.send(result);
    });

    if cfg.open_browser {
        open_url(&authorize)?;
    } else {
        tracing::info!(%authorize, "Auth0 authorize URL (open_browser=false)");
    }

    let (code, _returned_state) = tokio::time::timeout(Duration::from_secs(180), rx)
        .await
        .context("Auth0 login timed out (3 minutes)")?
        .context("Auth0 callback channel closed")??;

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

async fn accept_callback(listener: TcpListener, expected_state: &str) -> Result<(String, String)> {
    let (mut socket, _) = listener.accept().await.context("accept Auth0 callback")?;
    let mut buf = vec![0u8; 8192];
    let n = socket.read(&mut buf).await.context("read Auth0 callback")?;
    let req = String::from_utf8_lossy(&buf[..n]);
    let first_line = req.lines().next().unwrap_or_default();
    // GET /callback?code=...&state=... HTTP/1.1
    let path = first_line
        .split_whitespace()
        .nth(1)
        .context("malformed Auth0 callback request")?;
    let query = path
        .split_once('?')
        .map(|(_, q)| q)
        .unwrap_or("");
    let params = parse_query(query);
    if let Some(err) = params.get("error") {
        let desc = params
            .get("error_description")
            .map(String::as_str)
            .unwrap_or("");
        let body = html_page(
            "Sign-in failed",
            &format!("Auth0 error: {err} {desc}. You can close this window."),
        );
        write_http_response(&mut socket, 400, &body).await?;
        bail!("Auth0 error: {err} {desc}");
    }
    let code = params
        .get("code")
        .cloned()
        .context("Auth0 callback missing code")?;
    let state = params
        .get("state")
        .cloned()
        .context("Auth0 callback missing state")?;
    if state != expected_state {
        let body = html_page("Sign-in failed", "State mismatch. You can close this window.");
        write_http_response(&mut socket, 400, &body).await?;
        bail!("Auth0 state mismatch");
    }
    let body = html_page(
        "Signed in",
        "Mutande signed you in. You can close this window and return to the app.",
    );
    write_http_response(&mut socket, 200, &body).await?;
    Ok((code, state))
}

async fn write_http_response(
    socket: &mut tokio::net::TcpStream,
    status: u16,
    body: &str,
) -> Result<()> {
    let reason = match status {
        200 => "OK",
        400 => "Bad Request",
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

fn html_page(title: &str, message: &str) -> String {
    format!(
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>{title}</title></head>\
         <body style=\"font-family:system-ui;padding:2rem\"><h1>{title}</h1><p>{message}</p></body></html>"
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
        std::process::Command::new("open")
            .arg(url)
            .spawn()
            .context("open Auth0 authorize URL")?
            .wait()
            .ok();
        return Ok(());
    }
    #[cfg(not(target_os = "macos"))]
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
}
