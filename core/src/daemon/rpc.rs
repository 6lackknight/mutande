use std::sync::Arc;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::state::{HumanDecision, MutandeBundle, ResourceRequest};
use super::DaemonState;

pub const PARSE_ERROR: i32 = -32700;
pub const METHOD_NOT_FOUND: i32 = -32601;
pub const INVALID_PARAMS: i32 = -32602;
pub const INTERNAL_ERROR: i32 = -32603;

#[derive(Debug, Deserialize, Serialize)]
pub struct JsonRpcRequest {
    pub jsonrpc: Option<String>,
    pub id: Option<Value>,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct JsonRpcResponse {
    #[serde(default = "jsonrpc_version")]
    pub jsonrpc: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<JsonRpcError>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct JsonRpcError {
    pub code: i32,
    pub message: String,
}

fn jsonrpc_version() -> String {
    "2.0".to_string()
}

impl JsonRpcResponse {
    pub fn success(id: Option<Value>, result: Value) -> Self {
        Self {
            jsonrpc: jsonrpc_version(),
            id,
            result: Some(result),
            error: None,
        }
    }

    pub fn error(id: Option<Value>, code: i32, message: impl Into<String>) -> Self {
        Self {
            jsonrpc: jsonrpc_version(),
            id,
            result: None,
            error: Some(JsonRpcError {
                code,
                message: message.into(),
            }),
        }
    }
}

pub async fn handle_request(state: &Arc<DaemonState>, req: JsonRpcRequest) -> JsonRpcResponse {
    let id = req.id.clone();
    match dispatch(state, &req.method, req.params).await {
        Ok(result) => JsonRpcResponse::success(id, result),
        Err(err) => JsonRpcResponse::error(id, INTERNAL_ERROR, err.to_string()),
    }
}

async fn dispatch(state: &Arc<DaemonState>, method: &str, params: Value) -> Result<Value> {
    match method {
        "health" => Ok(serde_json::json!({
            "ok": true,
            "service": "mutande-core",
            "version": env!("CARGO_PKG_VERSION"),
        })),
        "auth_login" => {
            let hub_url = param_str(&params, "hub_url")?;
            let auth0_domain = optional_str(&params, "auth0_domain");
            let auth0_client_id = optional_str(&params, "auth0_client_id");
            let auth0_audience = optional_str(&params, "auth0_audience");
            let access_token = optional_str(&params, "access_token");
            let refresh_token = optional_str(&params, "refresh_token");
            let open_browser = params
                .get("open_browser")
                .and_then(|v| v.as_bool())
                .unwrap_or(true);
            let result = state
                .auth_login(
                    &hub_url,
                    auth0_domain.as_deref(),
                    auth0_client_id.as_deref(),
                    auth0_audience.as_deref(),
                    access_token.as_deref(),
                    refresh_token.as_deref(),
                    open_browser,
                )
                .await?;
            Ok(serde_json::to_value(result)?)
        }
        "create_org" => {
            let slug = param_str(&params, "slug")?;
            let name = optional_str(&params, "name");
            let handle = optional_str(&params, "handle");
            let result = state
                .create_org(&slug, name.as_deref(), handle.as_deref())
                .await?;
            Ok(serde_json::to_value(result)?)
        }
        "join_org" | "onboard" => {
            let invite_code = param_str(&params, "invite_code")?;
            let handle = optional_str(&params, "handle");
            let result = state.join_org(&invite_code, handle.as_deref()).await?;
            Ok(serde_json::to_value(result)?)
        }
        "register" => {
            anyhow::bail!(
                "register removed — use auth_login then create_org or join_org (Auth0)"
            );
        }
        "get_status" | "me" => {
            let status = state.get_status().await?;
            Ok(serde_json::to_value(status)?)
        }
        "list_contacts" => {
            let contacts = state.list_contacts().await?;
            Ok(serde_json::to_value(serde_json::json!({ "contacts": contacts }))?)
        }
        "list_threads" => {
            let filter = params
                .get("filter")
                .and_then(|v| serde_json::from_value(v.clone()).ok());
            let threads = state.list_threads(filter).await?;
            Ok(serde_json::to_value(serde_json::json!({ "threads": threads }))?)
        }
        "get_thread" => {
            let thread_id = param_str(&params, "thread_id")?;
            let detail = state.get_thread(&thread_id).await?;
            Ok(serde_json::to_value(detail)?)
        }
        "get_draft" => {
            let _ = state.sync_draft_from_hub().await;
            let draft = state.get_draft_plain();
            Ok(serde_json::to_value(draft)?)
        }
        "draft_add_question" => {
            let decision: HumanDecision = serde_json::from_value(params)?;
            state.merge_question(decision);
            state.persist_draft().await?;
            Ok(serde_json::json!({ "ok": true }))
        }
        "draft_add_resource" => {
            let req: ResourceRequest = serde_json::from_value(params)?;
            state.merge_resource_request(req);
            state.persist_draft().await?;
            Ok(serde_json::json!({ "ok": true }))
        }
        "forward_draft" => {
            let recipient = param_str(&params, "recipient")?;
            if let Some(notes) = optional_str(&params, "notes") {
                state.set_draft_notes(&notes);
            }
            let thread_id = state.forward_draft(&recipient).await?;
            Ok(serde_json::json!({ "thread_id": thread_id }))
        }
        "reply_to_thread" => {
            let thread_id = param_str(&params, "thread_id")?;
            let to_agent = optional_str(&params, "to_agent");
            let bundle: MutandeBundle = if let Some(b) = params.get("bundle") {
                serde_json::from_value(b.clone())?
            } else {
                serde_json::from_value(params.clone())?
            };
            state
                .reply_to_thread(&thread_id, bundle, to_agent.as_deref())
                .await?;
            Ok(serde_json::json!({ "ok": true }))
        }
        "close_thread" => {
            let thread_id = param_str(&params, "thread_id")?;
            state.close_thread(&thread_id).await?;
            Ok(serde_json::json!({ "ok": true }))
        }
        "mark_processed" => {
            let thread_id = param_str(&params, "thread_id")?;
            state.mark_processed(&thread_id);
            Ok(serde_json::json!({ "ok": true }))
        }
        "connect_host" => {
            let host = param_str(&params, "host")?;
            let result = super::connect_host::connect_host(&host, None)?;
            if host == "all" {
                for slug in ["cursor", "claude", "chatgpt"] {
                    let _ = state.register_connected_agent(slug).await;
                }
            } else {
                let _ = state.register_connected_agent(&host).await;
            }
            Ok(serde_json::to_value(result)?)
        }
        "register_agent" => {
            let slug = param_str(&params, "slug")?;
            let agent = state.register_connected_agent(&slug).await?;
            Ok(serde_json::to_value(agent)?)
        }
        "list_agents" => {
            let handle = optional_str(&params, "handle");
            if let Some(handle) = handle {
                let agents = state.list_agents_for_handle(&handle).await?;
                Ok(serde_json::json!({ "agents": agents }))
            } else {
                let list = state.list_agents().await?;
                Ok(serde_json::to_value(list)?)
            }
        }
        "set_default_agent" => {
            let agent_id = param_str(&params, "agent_id")?;
            let agent = state.set_default_agent(&agent_id).await?;
            Ok(serde_json::to_value(agent)?)
        }
        "rename_agent" => {
            let agent_id = param_str(&params, "agent_id")?;
            let slug = param_str(&params, "slug")?;
            let agent = state.rename_agent(&agent_id, &slug).await?;
            Ok(serde_json::to_value(agent)?)
        }
        "get_router" => {
            let router = state.get_router().await?;
            Ok(serde_json::to_value(router)?)
        }
        "set_router" => {
            let default_agent_id = optional_str(&params, "default_agent_id");
            let rules = params.get("rules").and_then(|v| {
                serde_json::from_value::<Vec<crate::hub_client::RoutingRule>>(v.clone()).ok()
            });
            let router = state
                .set_router(default_agent_id.as_deref(), rules)
                .await?;
            Ok(serde_json::to_value(router)?)
        }
        "get_safety_number" | "own_safety_number" => {
            let result = state.own_safety_number()?;
            Ok(serde_json::to_value(result)?)
        }
        "contact_safety_number" => {
            let handle = param_str(&params, "handle")?;
            let result = state.contact_safety_number(&handle).await?;
            Ok(serde_json::to_value(result)?)
        }
        "verify_contact" => {
            let handle = param_str(&params, "handle")?;
            let fingerprint = params
                .get("fingerprint")
                .or_else(|| params.get("fingerprint_or_uri"))
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow::anyhow!("missing param: fingerprint"))?;
            let result = state.verify_contact(&handle, fingerprint).await?;
            Ok(serde_json::to_value(result)?)
        }
        "forward_blob" => {
            let recipient = param_str(&params, "recipient")?;
            let subject = params
                .get("subject")
                .and_then(|v| v.as_str())
                .map(str::to_string);
            let plaintext = if let Some(b64) = params.get("content_base64").and_then(|v| v.as_str())
            {
                decode_base64(b64)?
            } else if let Some(path) = params.get("path").and_then(|v| v.as_str()) {
                std::fs::read(path)
                    .with_context(|| format!("read blob path {path}"))?
            } else {
                anyhow::bail!("missing param: content_base64 or path");
            };
            let thread_id = state
                .forward_blob(&recipient, &plaintext, subject.as_deref())
                .await?;
            Ok(serde_json::json!({ "thread_id": thread_id }))
        }
        "set_core_path" => {
            let path = param_str(&params, "path")?;
            state.set_mutande_core_path(&path)?;
            Ok(serde_json::json!({ "ok": true, "path": path }))
        }
        _ => anyhow::bail!("unknown method: {method}"),
    }
}

fn decode_base64(input: &str) -> Result<Vec<u8>> {
    // Standard base64 decode without extra crate dependency.
    fn val(c: u8) -> Option<u8> {
        match c {
            b'A'..=b'Z' => Some(c - b'A'),
            b'a'..=b'z' => Some(c - b'a' + 26),
            b'0'..=b'9' => Some(c - b'0' + 52),
            b'+' => Some(62),
            b'/' => Some(63),
            _ => None,
        }
    }
    let cleaned: Vec<u8> = input
        .bytes()
        .filter(|b| !b.is_ascii_whitespace())
        .collect();
    if cleaned.len() % 4 != 0 {
        anyhow::bail!("invalid base64 length");
    }
    let mut out = Vec::with_capacity(cleaned.len() / 4 * 3);
    for chunk in cleaned.chunks_exact(4) {
        let (a, b, c, d) = (chunk[0], chunk[1], chunk[2], chunk[3]);
        let av = val(a).context("invalid base64")?;
        let bv = val(b).context("invalid base64")?;
        let cv = if c == b'=' { 0 } else { val(c).context("invalid base64")? };
        let dv = if d == b'=' { 0 } else { val(d).context("invalid base64")? };
        let n = ((av as u32) << 18) | ((bv as u32) << 12) | ((cv as u32) << 6) | (dv as u32);
        out.push(((n >> 16) & 0xff) as u8);
        if c != b'=' {
            out.push(((n >> 8) & 0xff) as u8);
        }
        if d != b'=' {
            out.push((n & 0xff) as u8);
        }
    }
    Ok(out)
}

fn param_str(params: &Value, key: &str) -> Result<String> {
    params
        .get(key)
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| anyhow::anyhow!("missing param: {key}"))
}

fn optional_str(params: &Value, key: &str) -> Option<String> {
    params
        .get(key)
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::daemon::state::DaemonState;

    #[tokio::test]
    async fn health_rpc() {
        let state = Arc::new(DaemonState::new_in_memory_for_test().unwrap());
        let req = JsonRpcRequest {
            jsonrpc: Some("2.0".into()),
            id: Some(serde_json::json!(1)),
            method: "health".into(),
            params: serde_json::json!({}),
        };
        let resp = handle_request(&state, req).await;
        assert!(resp.error.is_none());
        let result = resp.result.unwrap();
        assert_eq!(result["ok"], true);
    }

    #[tokio::test]
    async fn draft_add_and_get() {
        let state = Arc::new(DaemonState::new_in_memory_for_test().unwrap());
        let req = JsonRpcRequest {
            jsonrpc: Some("2.0".into()),
            id: Some(serde_json::json!(1)),
            method: "draft_add_question".into(),
            params: serde_json::json!({
                "id": "q1",
                "kind": "question",
                "prompt": "test?"
            }),
        };
        let resp = handle_request(&state, req).await;
        assert!(resp.error.is_none());

        let get = JsonRpcRequest {
            jsonrpc: None,
            id: Some(serde_json::json!(2)),
            method: "get_draft".into(),
            params: serde_json::json!({}),
        };
        let resp2 = handle_request(&state, get).await;
        assert!(resp2.error.is_none());
        let result = resp2.result.unwrap();
        let questions = result["questions"].as_array().unwrap();
        assert_eq!(questions.len(), 1);
    }

    #[tokio::test]
    async fn connect_host_rejects_bad_host() {
        let state = Arc::new(DaemonState::new_in_memory_for_test().unwrap());
        let req = JsonRpcRequest {
            jsonrpc: Some("2.0".into()),
            id: Some(serde_json::json!(1)),
            method: "connect_host".into(),
            params: serde_json::json!({ "host": "vscode" }),
        };
        let resp = handle_request(&state, req).await;
        assert!(resp.error.is_some());
        assert!(resp.error.unwrap().message.contains("invalid host"));
    }

    #[tokio::test]
    async fn get_status_unconfigured_without_hub() {
        let state = Arc::new(DaemonState::new_in_memory_for_test().unwrap());
        let req = JsonRpcRequest {
            jsonrpc: Some("2.0".into()),
            id: Some(serde_json::json!(1)),
            method: "get_status".into(),
            params: serde_json::json!({}),
        };
        let resp = handle_request(&state, req).await;
        assert!(resp.error.is_none(), "{:?}", resp.error);
        let result = resp.result.unwrap();
        assert_eq!(result["configured"], false);
        assert!(result.get("handle").is_none() || result["handle"].is_null());
    }

    #[tokio::test]
    async fn auth_login_and_create_org_via_mock_hub() {
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let dir = tempfile::tempdir().unwrap();
        let cfg_path = dir.path().join("config.json");
        let state = Arc::new(
            DaemonState::new_in_memory_with_config_path(Some(cfg_path.clone())).unwrap(),
        );

        let server = MockServer::start().await;
        let me_needs = serde_json::json!({
            "auth0_sub": "auth0|1",
            "email": "a@x.com",
            "needs_onboarding": true,
            "onboarded": false
        });
        let me_ready = serde_json::json!({
            "auth0_sub": "auth0|1",
            "email": "a@x.com",
            "needs_onboarding": false,
            "onboarded": true,
            "user": {
                "id": "u1",
                "handle": "alice@acme",
                "org_id": "org-1",
                "role": "org_admin",
                "created_at": "2026-01-01T00:00:00Z"
            },
            "org": {
                "id": "org-1",
                "slug": "acme",
                "name": "Acme",
                "created_at": "2026-01-01T00:00:00Z"
            }
        });

        Mock::given(method("GET"))
            .and(path("/v1/me"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&me_needs))
            .mount(&server)
            .await;
        Mock::given(method("POST"))
            .and(path("/v1/orgs"))
            .respond_with(ResponseTemplate::new(201).set_body_json(&me_ready))
            .mount(&server)
            .await;
        Mock::given(method("POST"))
            .and(path("/v1/devices"))
            .respond_with(ResponseTemplate::new(201).set_body_json(&serde_json::json!({
                "device": {
                    "id": "d1",
                    "user_id": "u1",
                    "pubkey": "[0]",
                    "platform": "macos",
                    "created_at": "2026-01-01T00:00:00Z"
                }
            })))
            .mount(&server)
            .await;

        let login = JsonRpcRequest {
            jsonrpc: Some("2.0".into()),
            id: Some(serde_json::json!(1)),
            method: "auth_login".into(),
            params: serde_json::json!({
                "hub_url": server.uri(),
                "access_token": "auth0-at",
                "refresh_token": "auth0-rt",
                "auth0_domain": "tenant.example",
                "auth0_client_id": "native-id",
                "open_browser": false,
            }),
        };
        let resp = handle_request(&state, login).await;
        assert!(resp.error.is_none(), "{:?}", resp.error);
        let result = resp.result.unwrap();
        assert_eq!(result["signed_in"], true);
        assert_eq!(result["needs_onboarding"], true);
        assert_eq!(result["configured"], false);

        let saved: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&cfg_path).unwrap()).unwrap();
        assert_eq!(saved["access_token"], "auth0-at");
        assert_eq!(saved["refresh_token"], "auth0-rt");
        assert_eq!(saved["hub_url"], server.uri());

        // Remount /me as ready for get_status after create_org.
        let create = JsonRpcRequest {
            jsonrpc: Some("2.0".into()),
            id: Some(serde_json::json!(2)),
            method: "create_org".into(),
            params: serde_json::json!({
                "slug": "acme",
                "name": "Acme",
                "handle": "alice",
            }),
        };
        let created = handle_request(&state, create).await;
        assert!(created.error.is_none(), "{:?}", created.error);
        let body = created.result.unwrap();
        assert_eq!(body["handle"], "alice@acme");
        assert_eq!(body["org_id"], "org-1");
    }

    #[tokio::test]
    async fn register_rpc_removed() {
        let state = Arc::new(DaemonState::new_in_memory_for_test().unwrap());
        let req = JsonRpcRequest {
            jsonrpc: Some("2.0".into()),
            id: Some(serde_json::json!(1)),
            method: "register".into(),
            params: serde_json::json!({
                "invite_code": "x",
                "handle": "a@b",
                "hub_url": "http://localhost:8000",
            }),
        };
        let resp = handle_request(&state, req).await;
        assert!(resp.error.is_some());
        assert!(resp.error.unwrap().message.contains("auth_login"));
    }
}
