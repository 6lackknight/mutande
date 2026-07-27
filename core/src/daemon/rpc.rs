use std::sync::Arc;

use anyhow::Result;
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
        "register" | "onboard" => {
            let invite_code = param_str(&params, "invite_code")?;
            let handle = param_str(&params, "handle")?;
            let hub_url = param_str(&params, "hub_url")?;
            let result = state.register(&invite_code, &handle, &hub_url).await?;
            Ok(serde_json::to_value(result)?)
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
            let thread_id = state.forward_draft(&recipient).await?;
            Ok(serde_json::json!({ "thread_id": thread_id }))
        }
        "reply_to_thread" => {
            let thread_id = param_str(&params, "thread_id")?;
            let bundle: MutandeBundle = if let Some(b) = params.get("bundle") {
                serde_json::from_value(b.clone())?
            } else {
                serde_json::from_value(params.clone())?
            };
            state.reply_to_thread(&thread_id, bundle).await?;
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
            Ok(serde_json::to_value(result)?)
        }
        _ => anyhow::bail!("unknown method: {method}"),
    }
}

fn param_str(params: &Value, key: &str) -> Result<String> {
    params
        .get(key)
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| anyhow::anyhow!("missing param: {key}"))
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
    async fn register_persists_config_via_mock_hub() {
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let dir = tempfile::tempdir().unwrap();
        let cfg_path = dir.path().join("config.json");
        let state = Arc::new(
            DaemonState::new_in_memory_with_config_path(Some(cfg_path.clone())).unwrap(),
        );

        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/v1/auth/register"))
            .respond_with(ResponseTemplate::new(201).set_body_json(&serde_json::json!({
                "user": {
                    "id": "u1",
                    "handle": "alice@acme",
                    "org_id": "org-1",
                    "pubkey": "[0]",
                    "created_at": "2026-01-01T00:00:00Z"
                },
                "access_token": "access-jwt",
                "refresh_token": "refresh-jwt"
            })))
            .expect(1)
            .mount(&server)
            .await;

        let req = JsonRpcRequest {
            jsonrpc: Some("2.0".into()),
            id: Some(serde_json::json!(1)),
            method: "onboard".into(),
            params: serde_json::json!({
                "invite_code": "invite-abc",
                "handle": "alice@acme",
                "hub_url": server.uri(),
            }),
        };
        let resp = handle_request(&state, req).await;
        assert!(resp.error.is_none(), "{:?}", resp.error);
        let result = resp.result.unwrap();
        assert_eq!(result["handle"], "alice@acme");
        assert_eq!(result["org_id"], "org-1");

        let saved: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&cfg_path).unwrap()).unwrap();
        assert_eq!(saved["jwt"], "access-jwt");
        assert_eq!(saved["refresh_token"], "refresh-jwt");
        assert_eq!(saved["hub_url"], server.uri());

        // get_status is configured; /me not mocked → handle omitted.
        let status_req = JsonRpcRequest {
            jsonrpc: Some("2.0".into()),
            id: Some(serde_json::json!(2)),
            method: "me".into(),
            params: serde_json::json!({}),
        };
        let status = handle_request(&state, status_req).await;
        assert!(status.error.is_none());
        assert_eq!(status.result.unwrap()["configured"], true);
    }
}
