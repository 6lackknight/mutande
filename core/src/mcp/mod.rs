//! MCP stdio transport — tool definitions delegate to daemon.

mod protocol;
mod tools;

use std::io::{self, BufRead, Write};

use anyhow::{Context, Result};
use serde_json::{Value, json};

use crate::daemon::expand_path;
use crate::daemon::rpc::{JsonRpcRequest, JsonRpcResponse};

use protocol::{McpRequest, McpResponse, McpToolCallParams, McpToolsListResult};
use tools::tool_definitions;

const DAEMON_SOCKET: &str = "~/.mutande/daemon.sock";

pub async fn run_stdio() -> Result<()> {
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

async fn forward_tool_call(name: &str, arguments: Value) -> Result<String> {
    let daemon_method = tools::daemon_method_for_tool(name)
        .with_context(|| format!("unknown tool: {name}"))?;

    let req = JsonRpcRequest {
        jsonrpc: Some("2.0".into()),
        id: Some(json!(1)),
        method: daemon_method.to_string(),
        params: arguments,
    };

    let resp = call_daemon(&req).await?;
    if let Some(err) = resp.error {
        anyhow::bail!("{}", err.message);
    }
    Ok(serde_json::to_string_pretty(&resp.result.unwrap_or(json!({})))?)
}

async fn call_daemon(req: &JsonRpcRequest) -> Result<JsonRpcResponse> {
    let socket_path = expand_path(DAEMON_SOCKET);
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

#[cfg(test)]
mod tests {
    use super::*;
    use protocol::McpRequest;

    #[test]
    fn tool_definitions_include_send_and_read() {
        let defs = tool_definitions();
        assert!(defs.iter().any(|t| t.name == "list_threads"));
        assert!(defs.iter().any(|t| t.name == "forward_draft"));
        assert!(defs.iter().any(|t| t.name == "forward_blob"));
        assert!(defs.iter().any(|t| t.name == "get_safety_number"));
        assert!(defs.iter().any(|t| t.name == "verify_contact"));
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
