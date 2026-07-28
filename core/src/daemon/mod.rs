//! Local JSON-RPC API for Flutter UI and MCP subprocess.

mod auth0_defaults;
mod config;
mod connect_host;
mod http_bridge;
mod oauth;
pub mod rpc;
mod state;

pub use auth0_defaults::{
    AUTH0_AUDIENCE, AUTH0_DOMAIN, AUTH0_NATIVE_CLIENT_ID, HUB_URL as DEFAULT_HUB_URL,
};

pub use connect_host::{ConnectHostResult, connect_host};

pub use config::{
    DaemonConfig, ensure_http_token, http_token_path, load_config, save_config,
};
pub use state::FileIdentityStore;

use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};

use crate::hub_client::{HubClient, HubConfig};

use rpc::{JsonRpcRequest, JsonRpcResponse, handle_request};
use state::DaemonState;

/// Real login-home directory (passwd), not sandboxed `$HOME`.
///
/// macOS app-sandbox remaps `HOME` into `~/Library/Containers/…/Data`, which
/// makes `dirs::home_dir()` point at the container. MCP host configs and
/// `~/.mutande` must resolve to the user's actual home.
pub fn user_home_dir() -> Option<PathBuf> {
    #[cfg(unix)]
    {
        // SAFETY: getpwuid returns a pointer we only read; path is copied out.
        unsafe {
            let pw = libc::getpwuid(libc::getuid());
            if !pw.is_null() && !(*pw).pw_dir.is_null() {
                if let Ok(dir) = std::ffi::CStr::from_ptr((*pw).pw_dir).to_str() {
                    if !dir.is_empty() {
                        return Some(PathBuf::from(dir));
                    }
                }
            }
        }
    }
    dirs::home_dir()
}

pub fn expand_path(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        user_home_dir()
            .map(|home| home.join(rest))
            .unwrap_or_else(|| PathBuf::from(path))
    } else if path == "~" {
        user_home_dir().unwrap_or_else(|| PathBuf::from(path))
    } else {
        PathBuf::from(path)
    }
}

pub async fn run(socket_path: &str, http_bind: Option<&str>) -> Result<()> {
    let socket_path = expand_path(socket_path);
    ensure_mutande_dir(&socket_path)?;

    if socket_path.exists() {
        std::fs::remove_file(&socket_path).context("remove stale daemon socket")?;
    }

    let state = Arc::new(DaemonState::bootstrap()?);

    if let Some(bind) = http_bind {
        let token = config::ensure_http_token().context("ensure HTTP bridge token")?;
        tracing::info!(
            path = %config::http_token_path().display(),
            "HTTP bridge token ready (Authorization: Bearer / X-Mutande-Token)"
        );
        let http_state = Arc::clone(&state);
        let bind = bind.to_string();
        tokio::spawn(async move {
            if let Err(err) = http_bridge::run(http_state, &bind, &token).await {
                tracing::error!(error = %err, addr = %bind, "HTTP bridge stopped");
            }
        });
    }

    run_unix(socket_path, state).await
}

async fn run_unix(socket_path: PathBuf, state: Arc<DaemonState>) -> Result<()> {
    let listener = UnixListener::bind(&socket_path)
        .with_context(|| format!("bind {}", socket_path.display()))?;
    restrict_socket_permissions(&socket_path)?;

    tracing::info!(path = %socket_path.display(), "daemon listening");

    loop {
        let (stream, _) = listener.accept().await.context("accept connection")?;
        let state = Arc::clone(&state);
        tokio::spawn(async move {
            if let Err(err) = serve_connection(stream, state).await {
                tracing::warn!(error = %err, "connection error");
            }
        });
    }
}

async fn serve_connection(stream: UnixStream, state: Arc<DaemonState>) -> Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut lines = BufReader::new(reader).lines();

    while let Some(line) = lines.next_line().await.context("read line")? {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        let response = match serde_json::from_str::<JsonRpcRequest>(line) {
            Ok(req) => handle_request(&state, req).await,
            Err(err) => JsonRpcResponse::error(
                None,
                rpc::PARSE_ERROR,
                format!("invalid request: {err}"),
            ),
        };

        let out = serde_json::to_string(&response)? + "\n";
        writer.write_all(out.as_bytes()).await?;
        writer.flush().await?;
    }

    Ok(())
}

fn ensure_mutande_dir(socket_path: &Path) -> Result<()> {
    if let Some(parent) = socket_path.parent() {
        std::fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700))
                .with_context(|| format!("chmod 0700 {}", parent.display()))?;
        }
    }
    Ok(())
}

/// Owner-only socket after bind (macOS/unix). Best-effort if the FS ignores mode.
fn restrict_socket_permissions(socket_path: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(socket_path, std::fs::Permissions::from_mode(0o600))
            .with_context(|| format!("chmod 0600 {}", socket_path.display()))?;
    }
    let _ = socket_path;
    Ok(())
}

/// Build hub client from on-disk config when credentials exist.
pub fn hub_from_config(config: &DaemonConfig) -> Option<Result<HubClient>> {
    match (&config.hub_url, &config.access_token) {
        (Some(url), Some(token)) => Some(HubClient::new(
            HubConfig::new(url.clone(), token.clone())
                .with_refresh_token(config.refresh_token.clone())
                .with_auth0(config.auth0_domain.clone(), config.auth0_client_id.clone()),
        )),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::{DevicePubKey, DeviceSecretKey};
    use crypto_box::aead::OsRng;
    use crypto_box::SecretKey;
    use tempfile::tempdir;

    fn test_keypair() -> (DevicePubKey, DeviceSecretKey) {
        let sk = SecretKey::generate(&mut OsRng);
        let pk = sk.public_key();
        (
            DevicePubKey(pk.to_bytes()),
            DeviceSecretKey(sk.to_bytes()),
        )
    }

    #[tokio::test]
    async fn daemon_crypto_roundtrip_via_rpc() {
        let dir = tempdir().unwrap();
        let sock = dir.path().join("daemon.sock");
        let state = Arc::new(DaemonState::new_in_memory_for_test().unwrap());

        let listener = UnixListener::bind(&sock).unwrap();
        let accept_state = Arc::clone(&state);
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            serve_connection(stream, accept_state).await.unwrap();
        });

        let mut stream = UnixStream::connect(&sock).await.unwrap();
        let req = serde_json::json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "draft_add_question",
            "params": {
                "id": "q1",
                "prompt": "What is the plan?",
                "kind": "question"
            }
        });
        stream
            .write_all((req.to_string() + "\n").as_bytes())
            .await
            .unwrap();

        let mut reader = BufReader::new(stream);
        let mut line = String::new();
        reader.read_line(&mut line).await.unwrap();
        let resp: JsonRpcResponse = serde_json::from_str(line.as_str()).unwrap();
        assert!(resp.error.is_none(), "{:?}", resp.error);

        let get_req = serde_json::json!({
            "jsonrpc": "2.0",
            "id": 2,
            "method": "get_draft",
            "params": {}
        });
        reader.get_mut().write_all((get_req.to_string() + "\n").as_bytes()).await.unwrap();
        let mut line2 = String::new();
        reader.read_line(&mut line2).await.unwrap();
        let resp2: JsonRpcResponse = serde_json::from_str(line2.as_str()).unwrap();
        assert!(resp2.error.is_none());

        server.abort();
    }

    #[test]
    fn expand_tilde_path() {
        let home = user_home_dir().unwrap();
        assert_eq!(expand_path("~/foo"), home.join("foo"));
    }
}
