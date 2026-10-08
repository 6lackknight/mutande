//! Local daemon HTTP JSON-RPC for operator CLI (same bridge as Flutter).

use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use clap::Subcommand;
use serde_json::{Value, json};

use crate::daemon::rpc::{JsonRpcRequest, JsonRpcResponse};
use crate::daemon::{DEFAULT_HTTP_BIND, expand_path, http_token_path};

const RESERVED_AGENT_SLUGS: &[&str] = &["default", "all"];

#[derive(Subcommand)]
pub enum RpcCommands {
    /// Check daemon health via JSON-RPC `health`.
    Ping {
        #[arg(long, help = "Emit JSON instead of a one-line summary")]
        json: bool,
    },
    /// List, mint, or revoke hosted MCP connector keys (`mtc_…`).
    ///
    /// Uses the local HTTP bridge (`127.0.0.1:3847` by default) and
    /// `~/.mutande/daemon_http_token` — same as the Mac app, not the Unix MCP socket.
    Connectors {
        #[command(subcommand)]
        command: ConnectorsCommands,
    },
}

#[derive(Subcommand)]
pub enum ConnectorsCommands {
    List {
        #[arg(long)]
        json: bool,
    },
    Mint {
        #[arg(long, default_value = "Grok Bot")]
        label: String,
        #[arg(long, default_value = "grok")]
        slug: String,
        #[arg(long, help = "JSON on stdout (includes token); default human layout prints token on stdout and hints on stderr")]
        json: bool,
    },
    Revoke {
        connector_id: String,
        #[arg(long)]
        json: bool,
    },
}

pub async fn run(command: RpcCommands) -> Result<()> {
    match command {
        RpcCommands::Ping { json } => {
            let result = rpc_call("health", json!({})).await?;
            if json {
                print_json(result)?;
            } else {
                print_ping_human(&result);
            }
        }
        RpcCommands::Connectors { command } => match command {
            ConnectorsCommands::List { json } => {
                let result = rpc_call("list_mcp_connectors", json!({})).await?;
                if json {
                    print_json(result)?;
                } else {
                    print_connectors_list_human(&result);
                }
            }
            ConnectorsCommands::Mint { label, slug, json } => {
                let slug = normalize_connector_slug(&slug)?;
                let label = label.trim();
                if label.is_empty() {
                    bail!("label must not be empty");
                }
                let result = rpc_call(
                    "create_mcp_connector",
                    json!({ "label": label, "slug": slug }),
                )
                .await?;
                if json {
                    print_json(result)?;
                } else {
                    print_mint_human(&result)?;
                }
            }
            ConnectorsCommands::Revoke { connector_id, json } => {
                let result = rpc_call(
                    "revoke_mcp_connector",
                    json!({ "connector_id": connector_id }),
                )
                .await?;
                if json {
                    print_json(result)?;
                } else {
                    print_revoke_human(&result, &connector_id);
                }
            }
        },
    }
    Ok(())
}

/// Hub-aligned agent slug rules (`hub/store/address.ts`).
pub fn normalize_connector_slug(slug: &str) -> Result<String> {
    let s = slug.trim().to_lowercase();
    if s.is_empty() {
        bail!("agent slug must not be empty");
    }
    if s.len() > 32 {
        bail!("agent slug must be 1–32 characters");
    }
    if !s
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
    {
        bail!("agent slug must use lowercase letters, digits, or hyphens only");
    }
    if RESERVED_AGENT_SLUGS.contains(&s.as_str()) {
        bail!("agent slug '{s}' is reserved");
    }
    Ok(s)
}

fn print_json(value: Value) -> Result<()> {
    println!("{}", serde_json::to_string_pretty(&value)?);
    Ok(())
}

fn print_ping_human(result: &Value) {
    let service = result
        .get("service")
        .and_then(|v| v.as_str())
        .unwrap_or("mutande-core");
    let version = result
        .get("version")
        .and_then(|v| v.as_str())
        .unwrap_or("?");
    let ok = result.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
    if ok {
        println!("ok — {service} {version}");
    } else {
        println!("unexpected health response: {result}");
    }
}

fn print_connectors_list_human(result: &Value) {
    let Some(list) = result.get("connectors").and_then(|v| v.as_array()) else {
        println!("{result}");
        return;
    };
    if list.is_empty() {
        println!("No connector keys.");
        return;
    }
    for c in list {
        let label = c.get("label").and_then(|v| v.as_str()).unwrap_or("Connector");
        let slug = c.get("slug").and_then(|v| v.as_str()).unwrap_or("—");
        let prefix = c.get("prefix").and_then(|v| v.as_str()).unwrap_or("");
        let id = c.get("id").and_then(|v| v.as_str()).unwrap_or("");
        println!("{label}\t@{slug}\t{prefix}\tid={id}");
    }
}

fn print_revoke_human(result: &Value, connector_id: &str) {
    let ok = result.get("ok").and_then(|v| v.as_bool()).unwrap_or(true);
    if ok {
        println!("Revoked connector {connector_id}");
    } else {
        println!("{result}");
    }
}

fn print_mint_human(result: &Value) -> Result<()> {
    let token = result
        .get("token")
        .and_then(|v| v.as_str())
        .context("mint response missing token")?;
    let connector = result.get("connector").context("mint response missing connector")?;
    let label = connector
        .get("label")
        .and_then(|v| v.as_str())
        .unwrap_or("Connector");
    let slug = connector.get("slug").and_then(|v| v.as_str()).unwrap_or("grok");
    let id = connector.get("id").and_then(|v| v.as_str()).unwrap_or("");

    eprintln!("Copy this key now — mutande will not show it again.");
    eprintln!("The key line on stdout may be stored in shell history; use --json in scripts and protect the output.\n");
    println!("{token}");
    eprintln!(
        "\nConnector: {label} (slug {slug}, id {id})\n\
         Grok Plugins URL: https://mcp.mutande.online/mcp\n\
         Header X-Mutande-Connector: <key above>\n\
         Agent slug {slug} is stored on this key. X-Mutande-Agent-Slug overrides it when set."
    );
    Ok(())
}

async fn rpc_call(method: &str, params: Value) -> Result<Value> {
    let req = JsonRpcRequest {
        jsonrpc: Some("2.0".into()),
        id: Some(json!(1)),
        method: method.to_string(),
        params,
    };
    let resp = call_daemon_http(&req).await?;
    if let Some(err) = resp.error {
        bail!("{}", err.message);
    }
    Ok(resp.result.unwrap_or(json!({})))
}

fn cli_http_token_path() -> PathBuf {
    std::env::var("MUTANDE_HTTP_TOKEN_PATH")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .map(|s| expand_path(s.trim()))
        .unwrap_or_else(http_token_path)
}

async fn call_daemon_http(req: &JsonRpcRequest) -> Result<JsonRpcResponse> {
    let token_path = cli_http_token_path();
    let token = std::fs::read_to_string(&token_path)
        .with_context(|| {
            format!(
                "read {} — is mutande running with the HTTP bridge enabled?",
                token_path.display()
            )
        })?
        .trim()
        .to_string();
    if token.is_empty() {
        bail!("empty HTTP bridge token at {}", token_path.display());
    }

    let bind = std::env::var("MUTANDE_HTTP_BIND")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_HTTP_BIND.to_string());

    let url = format!("http://{bind}/rpc");
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(45))
        .build()
        .context("build HTTP client")?;
    let resp = client
        .post(&url)
        .header("Authorization", format!("Bearer {token}"))
        .header("Content-Type", "application/json")
        .json(req)
        .send()
        .await
        .map_err(|e| {
            if e.is_connect() {
                anyhow::anyhow!(
                    "{e:#}\n\
                     mutande-core rpc talks to the local HTTP bridge at {url} \
                     (not the Unix MCP socket). Start the Mac app or \
                     `mutande-core serve` with HTTP enabled (default bind {bind})."
                )
            } else {
                anyhow::anyhow!("{e:#}")
            }
        })
        .with_context(|| format!("POST {url}"))?;
    let status = resp.status();
    let body = resp.text().await.context("read HTTP response")?;
    if !status.is_success() {
        bail!("daemon HTTP {status}: {body}");
    }
    serde_json::from_str(&body).context("decode daemon HTTP JSON-RPC response")
}

#[cfg(test)]
mod tests {
    use super::*;
    use wiremock::matchers::{method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    #[test]
    fn normalize_slug_matches_hub_rules() {
        assert_eq!(normalize_connector_slug("COS").unwrap(), "cos");
        assert!(normalize_connector_slug("").is_err());
        assert!(normalize_connector_slug("default").is_err());
        assert!(normalize_connector_slug("bad slug").is_err());
    }

    #[tokio::test]
    async fn rpc_ping_uses_http_bridge() {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/rpc"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "jsonrpc": "2.0",
                "id": 1,
                "result": { "ok": true, "service": "mutande-core", "version": "9.9.9" }
            })))
            .mount(&server)
            .await;

        let dir = tempfile::tempdir().unwrap();
        let token_file = dir.path().join("daemon_http_token");
        std::fs::write(&token_file, "test-token\n").unwrap();

        unsafe {
            std::env::set_var("MUTANDE_HTTP_BIND", server.address().to_string());
            std::env::set_var(
                "MUTANDE_HTTP_TOKEN_PATH",
                token_file.to_string_lossy().as_ref(),
            );
        }

        let result = rpc_call("health", json!({})).await.unwrap();
        assert_eq!(result["version"], "9.9.9");

        unsafe {
            std::env::remove_var("MUTANDE_HTTP_BIND");
            std::env::remove_var("MUTANDE_HTTP_TOKEN_PATH");
        }
    }
}
