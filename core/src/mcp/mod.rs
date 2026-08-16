//! MCP stdio transport — tool definitions delegate to daemon.

mod collab_view;
mod protocol;
mod tools;

use std::io::{self, BufRead, Write};

use anyhow::{Context, Result};
use serde_json::{Value, json};

#[cfg(unix)]
use crate::daemon::{DEFAULT_SOCKET, expand_path};
use crate::daemon::rpc::{JsonRpcRequest, JsonRpcResponse};

use protocol::{McpRequest, McpResponse, McpToolCallParams, McpToolsListResult};
use tools::tool_definitions;

pub async fn run_stdio() -> Result<()> {
    if let Ok(slug) = std::env::var("MUTANDE_AGENT_SLUG") {
        let slug = slug.trim();
        if !slug.is_empty() {
            let _ = register_agent_on_connect(slug).await;
        }
    }

    let stdin = io::stdin();
    let mut stdout = io::stdout();

    for line in stdin.lock().lines() {
        let line = line.context("read stdin")?;
        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        let response = match serde_json::from_str::<McpRequest>(line) {
            Ok(req) => handle_mcp_request(req).await,
            Err(err) => Some(McpResponse::error(None, -32700, format!("parse error: {err}"))),
        };

        // MCP notifications must not get a JSON-RPC response (Claude Desktop rejects them).
        if let Some(response) = response {
            serde_json::to_writer(&mut stdout, &response)?;
            stdout.write_all(b"\n")?;
            stdout.flush()?;
        }
    }

    Ok(())
}

async fn handle_mcp_request(req: McpRequest) -> Option<McpResponse> {
    // Spec: notifications have no `id` and must not be answered.
    if req.id.is_none() || req.method.starts_with("notifications/") {
        return None;
    }

    let id = req.id.clone();
    Some(match req.method.as_str() {
        "initialize" => McpResponse::success(
            id,
            json!({
                "protocolVersion": "2024-11-05",
                "capabilities": { "tools": {} },
                "serverInfo": {
                    "name": "mutande-core",
                    "version": "0.1.0"
                }
            }),
        ),
        "tools/list" => McpResponse::success(
            id,
            serde_json::to_value(McpToolsListResult {
                tools: tool_definitions(),
            })
            .unwrap_or_else(|e| json!({ "tools": [], "error": e.to_string() })),
        ),
        "tools/call" => match serde_json::from_value::<McpToolCallParams>(
            req.params.unwrap_or(json!({})),
        ) {
            Ok(params) => match forward_tool_call(&params.name, params.arguments.unwrap_or(json!({}))).await {
                Ok(content) => McpResponse::success(
                    id,
                    json!({
                        "content": [{ "type": "text", "text": content }],
                        "isError": false
                    }),
                ),
                Err(err) => McpResponse::success(
                    id,
                    json!({
                        "content": [{ "type": "text", "text": err.to_string() }],
                        "isError": true
                    }),
                ),
            },
            Err(err) => McpResponse::error(id, -32602, format!("invalid tool params: {err}")),
        },
        "ping" => McpResponse::success(id, json!({})),
        _ => McpResponse::error(id, -32601, format!("method not found: {}", req.method)),
    })
}

async fn register_agent_on_connect(slug: &str) -> Result<()> {
    let req = JsonRpcRequest {
        jsonrpc: Some("2.0".into()),
        id: Some(json!(1)),
        method: "register_agent".to_string(),
        params: json!({ "slug": slug }),
    };
    let _ = call_daemon(&req).await?;
    Ok(())
}

async fn forward_tool_call(name: &str, arguments: Value) -> Result<String> {
    let daemon_method = tools::daemon_method_for_tool(name)
        .with_context(|| format!("unknown tool: {name}"))?;

    // Per-call identity: shared daemon state is overwritten by whichever host
    // last called register_agent. Always stamp MUTANDE_AGENT_SLUG on params.
    let params = inject_agent_slug(arguments);

    let req = JsonRpcRequest {
        jsonrpc: Some("2.0".into()),
        id: Some(json!(1)),
        method: daemon_method.to_string(),
        params,
    };

    let resp = call_daemon(&req).await?;
    if let Some(err) = resp.error {
        anyhow::bail!("{}", err.message);
    }
    let result = tools::present_tool_result(name, resp.result.unwrap_or(json!({})));
    Ok(serde_json::to_string_pretty(&result)?)
}

fn inject_agent_slug(mut arguments: Value) -> Value {
    let Ok(slug) = std::env::var("MUTANDE_AGENT_SLUG") else {
        return arguments;
    };
    let slug = slug.trim();
    if slug.is_empty() {
        return arguments;
    }
    if let Some(obj) = arguments.as_object_mut() {
        obj.insert("agent_slug".into(), json!(slug));
    }
    arguments
}

async fn call_daemon(req: &JsonRpcRequest) -> Result<JsonRpcResponse> {
    #[cfg(unix)]
    {
        call_daemon_unix(req).await
    }
    #[cfg(not(unix))]
    {
        call_daemon_http(req).await
    }
}

#[cfg(unix)]
async fn call_daemon_unix(req: &JsonRpcRequest) -> Result<JsonRpcResponse> {
    let socket_path = expand_path(DEFAULT_SOCKET);
    let mut stream = tokio::net::UnixStream::connect(&socket_path)
        .await
        .with_context(|| format!("connect to daemon at {}", socket_path.display()))?;

    let payload = serde_json::to_string(req)? + "\n";
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
    stream.write_all(payload.as_bytes()).await?;
    stream.flush().await?;

    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line).await?;
    serde_json::from_str(&line).context("decode daemon response")
}

/// Windows / non-Unix: MCP stdio talks to the local HTTP bridge (same as Flutter).
#[cfg(not(unix))]
async fn call_daemon_http(req: &JsonRpcRequest) -> Result<JsonRpcResponse> {
    use crate::daemon::{DEFAULT_HTTP_BIND, http_token_path};

    let token = std::fs::read_to_string(http_token_path())
        .context("read HTTP bridge token (~/.mutande/daemon_http_token) — is mutande-core serve running?")?
        .trim()
        .to_string();
    if token.is_empty() {
        anyhow::bail!("empty HTTP bridge token");
    }

    let url = format!("http://{}/rpc", DEFAULT_HTTP_BIND);
    let client = reqwest::Client::new();
    let resp = client
        .post(&url)
        .header("Authorization", format!("Bearer {token}"))
        .header("Content-Type", "application/json")
        .json(req)
        .send()
        .await
        .with_context(|| format!("POST {url}"))?;
    let status = resp.status();
    let body = resp.text().await.context("read HTTP response")?;
    if !status.is_success() {
        anyhow::bail!("daemon HTTP {status}: {body}");
    }
    serde_json::from_str(&body).context("decode daemon HTTP JSON-RPC response")
}

#[cfg(test)]
mod tests {
    use super::*;
    use protocol::McpRequest;

    #[test]
    fn tool_definitions_include_send_and_read() {
        let defs = tool_definitions();
        assert!(defs.iter().any(|t| t.name == "list_collabs"));
        assert!(defs.iter().any(|t| t.name == "get_collab"));
        assert!(defs.iter().any(|t| t.name == "create_card"));
        assert!(defs.iter().any(|t| t.name == "set_lane"));
        assert!(defs.iter().any(|t| t.name == "add_learning"));
        assert!(defs.iter().any(|t| t.name == "forward_draft"));
        assert!(defs.iter().any(|t| t.name == "forward_blob"));
        assert!(defs.iter().any(|t| t.name == "close_thread"));
        assert!(defs.iter().any(|t| t.name == "delete_thread"));
        assert!(defs.iter().any(|t| t.name == "get_safety_number"));
        assert!(defs.iter().any(|t| t.name == "verify_contact"));
        let list = defs.iter().find(|t| t.name == "list_threads").unwrap();
        assert!(list.input_schema["properties"]["collab_id"].is_object());
        let list_c = defs.iter().find(|t| t.name == "list_collabs").unwrap();
        assert!(list_c.description.contains("participate"));
    }

    #[test]
    fn tool_annotations_mark_reads_and_soft_writes() {
        let defs = tool_definitions();
        let list = defs.iter().find(|t| t.name == "list_threads").unwrap();
        let ann = list.annotations.as_ref().expect("list_threads annotations");
        assert_eq!(ann.read_only_hint, Some(true));
        assert_eq!(ann.destructive_hint, Some(false));

        let upvote = defs.iter().find(|t| t.name == "upvote_message").unwrap();
        let u = upvote.annotations.as_ref().expect("upvote annotations");
        assert_eq!(u.read_only_hint, Some(false));
        assert_eq!(u.destructive_hint, Some(false));

        let del = defs.iter().find(|t| t.name == "delete_thread").unwrap();
        let d = del.annotations.as_ref().expect("delete annotations");
        assert_eq!(d.destructive_hint, Some(true));
    }

    #[test]
    fn inject_agent_slug_stamps_env() {
        // SAFETY: test-only env mutation; not run in parallel with other env tests.
        unsafe { std::env::set_var("MUTANDE_AGENT_SLUG", "claude") };
        let out = inject_agent_slug(json!({ "thread_id": "t1", "bundle": {} }));
        assert_eq!(out["agent_slug"], "claude");
        assert_eq!(out["thread_id"], "t1");
        unsafe { std::env::remove_var("MUTANDE_AGENT_SLUG") };
    }

    #[tokio::test]
    async fn notifications_get_no_response() {
        let req = McpRequest {
            jsonrpc: Some("2.0".into()),
            id: None,
            method: "notifications/initialized".into(),
            params: None,
        };
        assert!(handle_mcp_request(req).await.is_none());
    }
}
