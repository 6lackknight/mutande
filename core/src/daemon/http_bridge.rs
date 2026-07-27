//! Dev HTTP JSON-RPC bridge for Flutter (POST /rpc on 127.0.0.1:3847).
//!
//! Requires a local bearer token (see `config::ensure_http_token`). Unix socket
//! IPC stays unauthenticated (filesystem-local MCP).

use std::sync::Arc;

use anyhow::{Context, Result};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

use super::rpc::{self, JsonRpcRequest, JsonRpcResponse, handle_request};
use super::state::DaemonState;

const MAX_BODY: usize = 1 << 20;

pub async fn run(state: Arc<DaemonState>, bind: &str, token: &str) -> Result<()> {
    let listener = TcpListener::bind(bind)
        .await
        .with_context(|| format!("bind HTTP bridge {bind}"))?;
    tracing::info!(addr = bind, "HTTP JSON-RPC bridge listening (token auth required)");

    let token = token.to_string();
    loop {
        let (stream, _) = listener.accept().await.context("accept HTTP connection")?;
        let state = Arc::clone(&state);
        let token = token.clone();
        tokio::spawn(async move {
            if let Err(err) = serve_connection(stream, state, &token).await {
                tracing::debug!(error = %err, "HTTP request failed");
            }
        });
    }
}

async fn serve_connection(
    mut stream: TcpStream,
    state: Arc<DaemonState>,
    token: &str,
) -> Result<()> {
    let mut header_buf = Vec::with_capacity(4096);
    let mut chunk = [0u8; 1024];

    loop {
        let n = stream.read(&mut chunk).await.context("read HTTP headers")?;
        if n == 0 {
            return Ok(());
        }
        header_buf.extend_from_slice(&chunk[..n]);
        if header_buf.windows(4).any(|w| w == b"\r\n\r\n") {
            break;
        }
        if header_buf.len() > 16_384 {
            write_http_response(&mut stream, 413, r#"{"error":"request too large"}"#).await?;
            return Ok(());
        }
    }

    let header_end = header_buf
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .context("incomplete HTTP headers")?
        + 4;
    let headers = String::from_utf8_lossy(&header_buf[..header_end]);
    let first_line = headers.lines().next().unwrap_or("");
    let parts: Vec<&str> = first_line.split_whitespace().collect();

    if parts.len() < 2 || parts[0] != "POST" || parts[1] != "/rpc" {
        write_http_response(&mut stream, 404, r#"{"error":"not found"}"#).await?;
        return Ok(());
    }

    if !authorize_headers(&headers, token) {
        write_http_response(&mut stream, 401, r#"{"error":"unauthorized"}"#).await?;
        return Ok(());
    }

    let content_length = parse_content_length(&headers).unwrap_or(0);
    if content_length > MAX_BODY {
        write_http_response(&mut stream, 413, r#"{"error":"body too large"}"#).await?;
        return Ok(());
    }

    let mut body = header_buf[header_end..].to_vec();
    while body.len() < content_length {
        let n = stream.read(&mut chunk).await.context("read HTTP body")?;
        if n == 0 {
            break;
        }
        body.extend_from_slice(&chunk[..n]);
    }
    let body = &body[..content_length.min(body.len())];

    let response = match serde_json::from_slice::<JsonRpcRequest>(body) {
        Ok(req) => handle_request(&state, req).await,
        Err(err) => JsonRpcResponse::error(
            None,
            rpc::PARSE_ERROR,
            format!("invalid request: {err}"),
        ),
    };

    let json = serde_json::to_string(&response)?;
    write_http_response(&mut stream, 200, &json).await
}

/// Accept `Authorization: Bearer <token>` or `X-Mutande-Token: <token>`.
pub fn authorize_headers(headers: &str, expected: &str) -> bool {
    if expected.is_empty() {
        return false;
    }
    for line in headers.lines().skip(1) {
        let Some((name, value)) = line.split_once(':') else {
            continue;
        };
        let value = value.trim();
        if name.eq_ignore_ascii_case("authorization") {
            let Some(bearer) = value
                .strip_prefix("Bearer ")
                .or_else(|| value.strip_prefix("bearer "))
            else {
                continue;
            };
            if tokens_equal(bearer.trim(), expected) {
                return true;
            }
        }
        if name.eq_ignore_ascii_case("x-mutande-token") && tokens_equal(value, expected) {
            return true;
        }
    }
    false
}

fn tokens_equal(a: &str, b: &str) -> bool {
    // Constant-time-ish compare for short local tokens.
    if a.len() != b.len() {
        return false;
    }
    a.bytes()
        .zip(b.bytes())
        .fold(0u8, |acc, (x, y)| acc | (x ^ y))
        == 0
}

async fn write_http_response(stream: &mut TcpStream, status: u16, body: &str) -> Result<()> {
    let status_text = match status {
        200 => "OK",
        401 => "Unauthorized",
        404 => "Not Found",
        413 => "Payload Too Large",
        _ => "Error",
    };
    let response = format!(
        "HTTP/1.1 {status} {status_text}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    stream
        .write_all(response.as_bytes())
        .await
        .context("write HTTP response")?;
    stream.flush().await.context("flush HTTP response")
}

fn parse_content_length(headers: &str) -> Option<usize> {
    for line in headers.lines().skip(1) {
        let (name, value) = line.split_once(':')?;
        if name.eq_ignore_ascii_case("content-length") {
            return value.trim().parse().ok();
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::daemon::config::ensure_http_token_at;
    use crate::daemon::state::DaemonState;
    use std::sync::Arc;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpStream;

    #[test]
    fn parse_content_length_header() {
        let headers = "POST /rpc HTTP/1.1\r\nContent-Length: 42\r\n\r\n";
        assert_eq!(parse_content_length(headers), Some(42));
    }

    #[test]
    fn authorize_bearer_and_x_header() {
        let token = "secret-token-abc";
        let bearer = format!("POST /rpc HTTP/1.1\r\nAuthorization: Bearer {token}\r\n\r\n");
        assert!(authorize_headers(&bearer, token));
        let x = format!("POST /rpc HTTP/1.1\r\nX-Mutande-Token: {token}\r\n\r\n");
        assert!(authorize_headers(&x, token));
        let bad = "POST /rpc HTTP/1.1\r\nAuthorization: Bearer wrong\r\n\r\n";
        assert!(!authorize_headers(bad, token));
        let missing = "POST /rpc HTTP/1.1\r\nContent-Type: application/json\r\n\r\n";
        assert!(!authorize_headers(missing, token));
    }

    #[test]
    fn ensure_http_token_reuses_existing() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("daemon_http_token");
        let a = ensure_http_token_at(&path).unwrap();
        let b = ensure_http_token_at(&path).unwrap();
        assert_eq!(a, b);
        assert_eq!(a.len(), 64);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&path).unwrap().permissions();
            assert_eq!(mode.mode() & 0o777, 0o600);
        }
    }

    #[tokio::test]
    async fn http_bridge_rejects_without_token_accepts_with() {
        let state = Arc::new(DaemonState::new_in_memory_for_test().unwrap());
        let token = "test-http-token-xyz";
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let serve_state = Arc::clone(&state);
        let serve_token = token.to_string();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            serve_connection(stream, serve_state, &serve_token)
                .await
                .unwrap();
        });

        let mut unauth = TcpStream::connect(addr).await.unwrap();
        let body = r#"{"jsonrpc":"2.0","id":1,"method":"health"}"#;
        let req = format!(
            "POST /rpc HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{body}",
            body.len()
        );
        unauth.write_all(req.as_bytes()).await.unwrap();
        let mut buf = vec![0u8; 1024];
        let n = unauth.read(&mut buf).await.unwrap();
        let resp = String::from_utf8_lossy(&buf[..n]);
        assert!(resp.starts_with("HTTP/1.1 401"), "{resp}");
        server.abort();

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let serve_state = Arc::clone(&state);
        let serve_token = token.to_string();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            serve_connection(stream, serve_state, &serve_token)
                .await
                .unwrap();
        });

        let mut auth = TcpStream::connect(addr).await.unwrap();
        let req = format!(
            "POST /rpc HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer {token}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{body}",
            body.len()
        );
        auth.write_all(req.as_bytes()).await.unwrap();
        let mut buf = vec![0u8; 2048];
        let n = auth.read(&mut buf).await.unwrap();
        let resp = String::from_utf8_lossy(&buf[..n]);
        assert!(resp.starts_with("HTTP/1.1 200"), "{resp}");
        assert!(resp.contains("\"ok\":true") || resp.contains("\"ok\": true"), "{resp}");
        server.abort();
    }
}
