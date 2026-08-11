//! HTTP JSON-RPC bridge for Flutter (`POST /rpc`) + inbox WebSocket (`GET /ws`).
//!
//! Requires a local bearer token (see `config::ensure_http_token`). Unix socket
//! IPC stays unauthenticated (filesystem-local MCP).

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use base64::Engine;
use sha1::{Digest, Sha1};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::broadcast;

use super::rpc::{self, JsonRpcRequest, JsonRpcResponse, handle_request};
use super::state::DaemonState;

const MAX_BODY: usize = 1 << 20;
const WS_MAGIC: &str = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const WS_HEARTBEAT: Duration = Duration::from_secs(30);

pub async fn run(state: Arc<DaemonState>, bind: &str, token: &str) -> Result<()> {
    let listener = TcpListener::bind(bind)
        .await
        .with_context(|| format!("bind HTTP bridge {bind}"))?;
    tracing::info!(addr = bind, "HTTP JSON-RPC + WebSocket bridge listening (token auth required)");

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

    if parts.len() < 2 {
        write_http_response(&mut stream, 404, r#"{"error":"not found"}"#).await?;
        return Ok(());
    }

    let method = parts[0];
    let path = parts[1].split('?').next().unwrap_or(parts[1]);

    if method == "GET" && path == "/ws" {
        return serve_websocket(stream, &headers, state, token).await;
    }

    if method != "POST" || path != "/rpc" {
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

async fn serve_websocket(
    mut stream: TcpStream,
    headers: &str,
    state: Arc<DaemonState>,
    token: &str,
) -> Result<()> {
    if !authorize_headers(headers, token) {
        write_http_response(&mut stream, 401, r#"{"error":"unauthorized"}"#).await?;
        return Ok(());
    }

    if !is_websocket_upgrade(headers) {
        write_http_response(&mut stream, 400, r#"{"error":"expected websocket upgrade"}"#).await?;
        return Ok(());
    }

    let Some(key) = header_value(headers, "sec-websocket-key") else {
        write_http_response(&mut stream, 400, r#"{"error":"missing Sec-WebSocket-Key"}"#).await?;
        return Ok(());
    };

    let accept = ws_accept_key(key);
    let response = format!(
        "HTTP/1.1 101 Switching Protocols\r\n\
Upgrade: websocket\r\n\
Connection: Upgrade\r\n\
Sec-WebSocket-Accept: {accept}\r\n\
\r\n"
    );
    stream.write_all(response.as_bytes()).await?;
    stream.flush().await?;

    let mut events = state.event_hub().subscribe();
    let mut subscribed = false;
    let mut heartbeat = tokio::time::interval(WS_HEARTBEAT);
    heartbeat.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let mut read_buf = Vec::new();

    loop {
        tokio::select! {
            biased;
            frame = read_ws_text_frame(&mut stream, &mut read_buf) => {
                match frame {
                    Ok(None) => return Ok(()), // close
                    Ok(Some(text)) => {
                        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
                            let op = v.get("op").and_then(|x| x.as_str()).unwrap_or("");
                            let channel = v.get("channel").and_then(|x| x.as_str()).unwrap_or("inbox");
                            if op == "subscribe" && channel == "inbox" {
                                subscribed = true;
                                let ack = serde_json::json!({
                                    "event": "subscribed",
                                    "channel": "inbox",
                                });
                                write_ws_text(&mut stream, &ack.to_string()).await?;
                            } else if op == "ping" {
                                write_ws_text(&mut stream, r#"{"event":"pong"}"#).await?;
                            }
                        }
                    }
                    Err(err) => {
                        tracing::debug!(error = %err, "websocket read failed");
                        return Ok(());
                    }
                }
            }
            msg = events.recv() => {
                match msg {
                    Ok(ev) if subscribed => {
                        let json = serde_json::to_string(&ev)?;
                        if write_ws_text(&mut stream, &json).await.is_err() {
                            return Ok(());
                        }
                    }
                    Ok(_) => {}
                    Err(broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(broadcast::error::RecvError::Closed) => return Ok(()),
                }
            }
            _ = heartbeat.tick() => {
                if subscribed {
                    let _ = write_ws_text(&mut stream, r#"{"event":"heartbeat"}"#).await;
                }
            }
        }
    }
}

fn is_websocket_upgrade(headers: &str) -> bool {
    let mut upgrade = false;
    let mut connection_upgrade = false;
    for line in headers.lines().skip(1) {
        let Some((name, value)) = line.split_once(':') else {
            continue;
        };
        let value = value.trim();
        if name.eq_ignore_ascii_case("upgrade") && value.eq_ignore_ascii_case("websocket") {
            upgrade = true;
        }
        if name.eq_ignore_ascii_case("connection")
            && value.to_ascii_lowercase().contains("upgrade")
        {
            connection_upgrade = true;
        }
    }
    upgrade && connection_upgrade
}

fn header_value<'a>(headers: &'a str, name: &str) -> Option<&'a str> {
    for line in headers.lines().skip(1) {
        let Some((n, value)) = line.split_once(':') else {
            continue;
        };
        if n.eq_ignore_ascii_case(name) {
            return Some(value.trim());
        }
    }
    None
}

fn ws_accept_key(client_key: &str) -> String {
    let mut hasher = Sha1::new();
    hasher.update(client_key.as_bytes());
    hasher.update(WS_MAGIC.as_bytes());
    base64::engine::general_purpose::STANDARD.encode(hasher.finalize())
}

async fn write_ws_text(stream: &mut TcpStream, text: &str) -> Result<()> {
    let payload = text.as_bytes();
    let mut frame = Vec::with_capacity(2 + payload.len() + 8);
    frame.push(0x81); // FIN + text
    if payload.len() < 126 {
        frame.push(payload.len() as u8);
    } else if payload.len() <= 65535 {
        frame.push(126);
        frame.extend_from_slice(&(payload.len() as u16).to_be_bytes());
    } else {
        frame.push(127);
        frame.extend_from_slice(&(payload.len() as u64).to_be_bytes());
    }
    frame.extend_from_slice(payload);
    stream.write_all(&frame).await?;
    stream.flush().await?;
    Ok(())
}

/// Read one text frame; `Ok(None)` on close. Handles ping/pong/control.
async fn read_ws_text_frame(
    stream: &mut TcpStream,
    leftover: &mut Vec<u8>,
) -> Result<Option<String>> {
    loop {
        while leftover.len() < 2 {
            let mut chunk = [0u8; 1024];
            let n = stream.read(&mut chunk).await?;
            if n == 0 {
                return Ok(None);
            }
            leftover.extend_from_slice(&chunk[..n]);
        }

        let b0 = leftover[0];
        let b1 = leftover[1];
        let opcode = b0 & 0x0f;
        let masked = (b1 & 0x80) != 0;
        let mut len = (b1 & 0x7f) as usize;
        let mut header_len = 2usize;

        if len == 126 {
            while leftover.len() < 4 {
                let mut chunk = [0u8; 1024];
                let n = stream.read(&mut chunk).await?;
                if n == 0 {
                    return Ok(None);
                }
                leftover.extend_from_slice(&chunk[..n]);
            }
            len = u16::from_be_bytes([leftover[2], leftover[3]]) as usize;
            header_len = 4;
        } else if len == 127 {
            while leftover.len() < 10 {
                let mut chunk = [0u8; 1024];
                let n = stream.read(&mut chunk).await?;
                if n == 0 {
                    return Ok(None);
                }
                leftover.extend_from_slice(&chunk[..n]);
            }
            let mut bytes = [0u8; 8];
            bytes.copy_from_slice(&leftover[2..10]);
            len = u64::from_be_bytes(bytes) as usize;
            header_len = 10;
        }

        let mask_len = if masked { 4 } else { 0 };
        let total = header_len + mask_len + len;
        while leftover.len() < total {
            let mut chunk = [0u8; 4096];
            let n = stream.read(&mut chunk).await?;
            if n == 0 {
                return Ok(None);
            }
            leftover.extend_from_slice(&chunk[..n]);
        }

        let mut payload = leftover[header_len + mask_len..total].to_vec();
        if masked {
            let mask = &leftover[header_len..header_len + 4];
            for (i, b) in payload.iter_mut().enumerate() {
                *b ^= mask[i % 4];
            }
        }
        leftover.drain(..total);

        match opcode {
            0x8 => return Ok(None), // close
            0x9 => {
                // ping → pong
                let mut pong = Vec::with_capacity(2 + payload.len());
                pong.push(0x8A);
                pong.push(payload.len() as u8);
                pong.extend_from_slice(&payload);
                stream.write_all(&pong).await?;
                stream.flush().await?;
            }
            0xA => {} // pong
            0x1 => {
                let text = String::from_utf8(payload).context("websocket text utf8")?;
                return Ok(Some(text));
            }
            0x2 => bail!("binary websocket frames not supported"),
            _ => {}
        }
    }
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
        400 => "Bad Request",
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
    fn ws_accept_key_matches_rfc6455_example() {
        // RFC 6455 §1.3 example
        let key = "dGhlIHNhbXBsZSBub25jZQ==";
        assert_eq!(ws_accept_key(key), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=");
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

    #[tokio::test]
    async fn websocket_rejects_without_token() {
        let state = Arc::new(DaemonState::new_in_memory_for_test().unwrap());
        let token = "ws-token";
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let serve_state = Arc::clone(&state);
        let serve_token = token.to_string();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let _ = serve_connection(stream, serve_state, &serve_token).await;
        });

        let mut c = TcpStream::connect(addr).await.unwrap();
        let req = "GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n";
        c.write_all(req.as_bytes()).await.unwrap();
        let mut buf = vec![0u8; 512];
        let n = c.read(&mut buf).await.unwrap();
        let resp = String::from_utf8_lossy(&buf[..n]);
        assert!(resp.starts_with("HTTP/1.1 401"), "{resp}");
        server.abort();
    }

    #[tokio::test]
    async fn websocket_subscribe_receives_inbox_changed() {
        let state = Arc::new(DaemonState::new_in_memory_for_test().unwrap());
        let token = "ws-token-ok";
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let serve_state = Arc::clone(&state);
        let serve_token = token.to_string();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let _ = serve_connection(stream, serve_state, &serve_token).await;
        });

        let mut c = TcpStream::connect(addr).await.unwrap();
        let req = format!(
            "GET /ws HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer {token}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
        );
        c.write_all(req.as_bytes()).await.unwrap();
        let mut buf = vec![0u8; 1024];
        let n = c.read(&mut buf).await.unwrap();
        let resp = String::from_utf8_lossy(&buf[..n]);
        assert!(resp.starts_with("HTTP/1.1 101"), "{resp}");

        // Client text frame (masked): subscribe
        let payload = br#"{"op":"subscribe","channel":"inbox"}"#;
        let mask = [1u8, 2, 3, 4];
        let mut frame = vec![0x81, 0x80 | (payload.len() as u8)];
        frame.extend_from_slice(&mask);
        for (i, b) in payload.iter().enumerate() {
            frame.push(b ^ mask[i % 4]);
        }
        c.write_all(&frame).await.unwrap();

        // Read subscribed ack
        let mut ack_buf = vec![0u8; 256];
        let n = tokio::time::timeout(Duration::from_secs(2), c.read(&mut ack_buf))
            .await
            .unwrap()
            .unwrap();
        let ack = &ack_buf[..n];
        assert_eq!(ack[0] & 0x0f, 0x1);
        let plen = (ack[1] & 0x7f) as usize;
        let text = String::from_utf8_lossy(&ack[2..2 + plen]);
        assert!(text.contains("subscribed"), "{text}");

        state.notify_inbox_changed();

        let mut ev_buf = vec![0u8; 512];
        let n = tokio::time::timeout(Duration::from_secs(2), c.read(&mut ev_buf))
            .await
            .unwrap()
            .unwrap();
        let ev = &ev_buf[..n];
        let plen = (ev[1] & 0x7f) as usize;
        let text = String::from_utf8_lossy(&ev[2..2 + plen]);
        assert!(text.contains("inbox_changed"), "{text}");
        assert!(text.contains("\"revision\""), "{text}");

        server.abort();
    }
}
