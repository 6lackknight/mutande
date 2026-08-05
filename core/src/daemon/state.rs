use std::collections::HashSet;
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result, bail};
use crypto_box::aead::OsRng;
use crypto_box::SecretKey;
use serde::{Deserialize, Serialize};

use crate::address::{
    agent_suffix, bare_handle, is_broadcast_handle, is_my_agents_handle, parse_display_address,
    strip_agent_suffix, AddressKind,
};
use crate::crypto::{
    DevicePubKey, DeviceSecretKey, Envelope, IdentityStore, MemoryStore, StoreError,
    fingerprints_match, open, open_from_bytes, safety_number, safety_uri, seal, seal_to_temp,
    with_blob_id,
};

#[cfg(target_os = "macos")]
use crate::crypto::KeychainIdentityStore;
use crate::hub_client::{
    Agent, Contact, HubClient, MeResponse, ThreadDetail, ThreadFilter, ThreadKind, ThreadMessage,
    ThreadMeta, ThreadStatus, YourStatus, pubkey_from_hub_string,
};

use super::config::{DaemonConfig, config_path, load_config, save_config_at};
use super::oauth::{self, Auth0NativeConfig};

/// Product ping kinds — `health` gets daemon auto-pong; `thread` expects agent mail reply.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PingKind {
    Health,
    Thread,
}

impl PingKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            PingKind::Health => "health",
            PingKind::Thread => "thread",
        }
    }

    pub fn parse(s: &str) -> Result<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "health" => Ok(PingKind::Health),
            "thread" => Ok(PingKind::Thread),
            other => bail!("invalid ping kind: {other} (expected health|thread)"),
        }
    }
}

/// Plaintext draft matching proto/bundle.schema.json (subset used in v1).
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct MutandeBundle {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub subject: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub questions: Vec<HumanDecision>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub resource_requests: Vec<ResourceRequest>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub resources: Vec<BundleResource>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub answers: Vec<BundleAnswer>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ping_kind: Option<PingKind>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub in_reply_to: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct HumanDecision {
    pub id: String,
    pub kind: String,
    pub prompt: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub options: Option<Vec<String>>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct ResourceRequest {
    pub id: String,
    pub description: String,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct BundleResource {
    pub name: String,
    pub mime: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct BundleAnswer {
    pub question_id: String,
    pub answer: String,
}

/// Thread message after local open attempt — agents get `bundle` when this device can decrypt.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct OpenedThreadMessage {
    pub id: String,
    pub thread_id: String,
    pub from_user_id: String,
    pub from_handle: String,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sender_only: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_message_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bundle: Option<MutandeBundle>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub envelope: Option<Envelope>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub open_error: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub upvotes: Option<crate::hub_client::MessageUpvoteSummary>,
}

/// Hub thread metadata plus locally opened (or failed) messages.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct OpenedThreadDetail {
    pub thread: ThreadMeta,
    pub messages: Vec<OpenedThreadMessage>,
}

/// Result of `forward_draft` / `forward_blob` / `ping`.
/// Bare `@all` is one shared group thread; 1:1 addresses stay single-thread.
#[derive(Debug, Clone)]
pub struct ForwardThreadsResult {
    /// Hub `to` addresses, same order as [`Self::thread_ids`].
    pub recipients: Vec<String>,
    pub thread_ids: Vec<String>,
}

/// File-backed identity store (~/.mutande/device.json). Used on non-macOS
/// and as a migration source when Keychain is empty.
pub struct FileIdentityStore {
    path: PathBuf,
    memory: MemoryStore,
}

impl FileIdentityStore {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            memory: MemoryStore::new(),
        }
    }

    pub fn default_path() -> PathBuf {
        super::expand_path("~/.mutande/device.json")
    }

    fn load_from_disk(&self) -> Result<()> {
        if !self.path.exists() {
            return Ok(());
        }
        let data = fs::read_to_string(&self.path)
            .with_context(|| format!("read {}", self.path.display()))?;
        let stored: StoredDeviceKey = serde_json::from_str(&data).context("parse device.json")?;
        if stored.public.len() != 32 {
            bail!("device.json corrupt");
        }
        let secret = match &stored.secret {
            Some(secret) if secret.len() == 32 => {
                let mut sk = [0u8; 32];
                sk.copy_from_slice(secret);
                DeviceSecretKey(sk)
            }
            Some(_) => bail!("device.json corrupt"),
            None => return Ok(()),
        };
        let mut pk = [0u8; 32];
        pk.copy_from_slice(&stored.public);
        self.memory
            .save_device_keypair(&DevicePubKey(pk), &secret)
            .map_err(|e| anyhow::anyhow!("{e}"))?;
        Ok(())
    }

    fn persist(&self, public: &DevicePubKey, secret: &DeviceSecretKey) -> Result<()> {
        let stored = StoredDeviceKey {
            public: public.0.to_vec(),
            secret: Some(secret.0.to_vec()),
        };
        super::config::write_restricted_file(
            &self.path,
            serde_json::to_string_pretty(&stored)?,
        )
        .with_context(|| format!("write {}", self.path.display()))
    }

    /// Rewrite device.json with public key only (strip plaintext secret).
    pub fn persist_public_only(&self, public: &DevicePubKey) -> Result<()> {
        let stored = StoredDeviceKey {
            public: public.0.to_vec(),
            secret: None,
        };
        super::config::write_restricted_file(
            &self.path,
            serde_json::to_string_pretty(&stored)?,
        )
        .with_context(|| format!("write {}", self.path.display()))
    }
}

#[derive(Serialize, Deserialize)]
struct StoredDeviceKey {
    public: Vec<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    secret: Option<Vec<u8>>,
}

impl IdentityStore for FileIdentityStore {
    fn load_device_secret(&self) -> Result<DeviceSecretKey, StoreError> {
        self.memory.load_device_secret()
    }

    fn device_public(&self) -> Result<DevicePubKey, StoreError> {
        self.memory.device_public()
    }

    fn save_device_keypair(
        &self,
        public: &DevicePubKey,
        secret: &DeviceSecretKey,
    ) -> Result<(), StoreError> {
        self.memory.save_device_keypair(public, secret)?;
        self.persist(public, secret)
            .map_err(|_| StoreError::Failed)?;
        Ok(())
    }
}

fn ensure_device_keypair(identity: &dyn IdentityStore) -> Result<()> {
    if identity.device_public().is_err() {
        tracing::info!("generating ephemeral device keypair");
        let sk = SecretKey::generate(&mut OsRng);
        let pk = sk.public_key();
        identity
            .save_device_keypair(
                &DevicePubKey(pk.to_bytes()),
                &DeviceSecretKey(sk.to_bytes()),
            )
            .map_err(|e| anyhow::anyhow!("{e}"))?;
    }
    Ok(())
}

#[cfg(target_os = "macos")]
fn bootstrap_identity() -> Result<Box<dyn IdentityStore>> {
    let keychain = KeychainIdentityStore::new();
    keychain
        .load_from_keychain()
        .map_err(|e| anyhow::anyhow!("{e}"))?;

    if keychain.device_public().is_err() {
        let file = FileIdentityStore::new(FileIdentityStore::default_path());
        file.load_from_disk()?;
        if let (Ok(pk), Ok(sk)) = (file.device_public(), file.load_device_secret()) {
            tracing::info!("migrating device secret from device.json to Keychain");
            keychain
                .save_device_keypair(&pk, &sk)
                .map_err(|e| anyhow::anyhow!("{e}"))?;
            // Stop storing plaintext secret on disk — fail loud if strip fails.
            file.persist_public_only(&pk).with_context(|| {
                format!(
                    "Keychain migrate succeeded but failed to strip secret from {}",
                    file.path.display()
                )
            })?;
        }
    }

    ensure_device_keypair(&keychain)?;
    Ok(Box::new(keychain))
}

#[cfg(not(target_os = "macos"))]
fn bootstrap_identity() -> Result<Box<dyn IdentityStore>> {
    let identity = FileIdentityStore::new(FileIdentityStore::default_path());
    identity.load_from_disk()?;
    ensure_device_keypair(&identity)?;
    Ok(Box::new(identity))
}

/// Result of create-org / join-invite onboarding.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct OnboardResult {
    pub handle: String,
    pub org_id: String,
}

/// Daemon + hub session status (no secrets).
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct StatusResult {
    /// Onboarded with a handle — ready for E2E mail UI.
    pub configured: bool,
    /// Auth0 access token + hub_url present.
    #[serde(default)]
    pub signed_in: bool,
    #[serde(default)]
    pub needs_onboarding: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hub_url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub handle: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub org_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub connected_agent: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default_agent: Option<String>,
}

/// Safety-number compare result (no raw pubkey in agent/MCP responses).
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct SafetyNumberResult {
    pub handle: String,
    pub fingerprint: String,
    pub uri: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub verified: Option<bool>,
}


pub struct DaemonState {
    config: Arc<Mutex<DaemonConfig>>,
    /// Override config.json path (tests); `None` → `~/.mutande/config.json`.
    config_path: Option<PathBuf>,
    identity: Box<dyn IdentityStore>,
    hub: Mutex<Option<HubClient>>,
    draft: Mutex<MutandeBundle>,
    draft_id: Mutex<Option<String>>,
    processed_threads: Mutex<HashSet<String>>,
    connected_agent_slug: Mutex<Option<String>>,
}

impl DaemonState {
    /// Inline envelope comfort zone (~40KB plaintext). Larger → R2 blob path.
    pub const INLINE_COMFORT_ZONE: usize = 40 * 1024;

    pub fn bootstrap() -> Result<Self> {
        let loaded = load_config().unwrap_or_default();
        let identity = bootstrap_identity()?;
        let config = Arc::new(Mutex::new(loaded.clone()));
        let hub = match (&loaded.hub_url, &loaded.access_token) {
            (Some(url), Some(token)) => Some(make_hub_client(
                url,
                token,
                loaded.refresh_token.clone(),
                loaded.auth0_domain.clone(),
                loaded.auth0_client_id.clone(),
                Arc::clone(&config),
                None,
            )?),
            _ => None,
        };

        let state = Self {
            config,
            config_path: None,
            identity,
            hub: Mutex::new(hub),
            draft: Mutex::new(MutandeBundle::default()),
            draft_id: Mutex::new(None),
            processed_threads: Mutex::new(HashSet::new()),
            connected_agent_slug: Mutex::new(None),
        };
        // So Connect AI / MCP host configs resolve the bundled sidecar absolute path.
        let _ = state.persist_own_exe_path();
        Ok(state)
    }

    /// Record absolute path of this `mutande-core` binary in config.json.
    pub fn persist_own_exe_path(&self) -> Result<()> {
        let exe = std::env::current_exe().context("current_exe")?;
        let abs = exe
            .canonicalize()
            .unwrap_or(exe)
            .to_string_lossy()
            .into_owned();
        self.set_mutande_core_path(&abs)
    }

    pub fn set_mutande_core_path(&self, path: &str) -> Result<()> {
        let path = path.trim();
        if path.is_empty() {
            bail!("mutande_core_path empty");
        }
        let mut cfg = self.config.lock().unwrap();
        if cfg.mutande_core_path.as_deref() == Some(path) {
            return Ok(());
        }
        cfg.mutande_core_path = Some(path.to_string());
        let to_save = cfg.clone();
        drop(cfg);
        let dest = self
            .config_path
            .clone()
            .unwrap_or_else(config_path);
        save_config_at(&dest, &to_save)
    }

    #[cfg(test)]
    pub fn new_in_memory_for_test() -> Result<Self> {
        Self::new_in_memory_with_config_path(None)
    }

    #[cfg(test)]
    pub fn new_in_memory_with_config_path(config_path: Option<PathBuf>) -> Result<Self> {
        let sk = SecretKey::generate(&mut OsRng);
        let pk = sk.public_key();
        let store = MemoryStore::new();
        store
            .save_device_keypair(
                &DevicePubKey(pk.to_bytes()),
                &DeviceSecretKey(sk.to_bytes()),
            )
            .map_err(|e| anyhow::anyhow!("{e}"))?;
        Ok(Self {
            config: Arc::new(Mutex::new(DaemonConfig::default())),
            config_path,
            identity: Box::new(store),
            hub: Mutex::new(None),
            draft: Mutex::new(MutandeBundle::default()),
            draft_id: Mutex::new(None),
            processed_threads: Mutex::new(HashSet::new()),
            connected_agent_slug: Mutex::new(None),
        })
    }

    #[cfg(test)]
    pub fn attach_hub_for_test(&self, hub: HubClient) {
        *self.hub.lock().unwrap() = Some(hub);
    }

    #[cfg(test)]
    pub fn set_connected_agent_slug_for_test(&self, slug: Option<&str>) {
        *self.connected_agent_slug.lock().unwrap() = slug.map(str::to_string);
    }

    fn hub_client(&self) -> Option<HubClient> {
        self.hub.lock().unwrap().clone()
    }

    /// Auth0 login (loopback PKCE or injected access token), then hub `/me`.
    /// If already onboarded, registers this device pubkey.
    pub async fn auth_login(
        &self,
        hub_url: &str,
        auth0_domain: Option<&str>,
        auth0_client_id: Option<&str>,
        auth0_audience: Option<&str>,
        access_token: Option<&str>,
        refresh_token: Option<&str>,
        open_browser: bool,
    ) -> Result<StatusResult> {
        let hub_url = hub_url.trim().trim_end_matches('/');
        if hub_url.is_empty() {
            bail!("missing param: hub_url");
        }

        let domain = resolve_auth0_domain(auth0_domain)?;
        let client_id = resolve_auth0_client_id(auth0_client_id)?;
        let audience = resolve_auth0_audience(auth0_audience);

        let (access, refresh) = if let Some(at) = access_token.map(str::trim).filter(|s| !s.is_empty())
        {
            (
                at.to_string(),
                refresh_token
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(str::to_string)
                    .or_else(|| std::env::var("MUTANDE_AUTH0_REFRESH_TOKEN").ok()),
            )
        } else if let Ok(env_at) = std::env::var("MUTANDE_AUTH0_ACCESS_TOKEN") {
            let at = env_at.trim().to_string();
            if at.is_empty() {
                bail!("MUTANDE_AUTH0_ACCESS_TOKEN is empty");
            }
            (
                at,
                std::env::var("MUTANDE_AUTH0_REFRESH_TOKEN")
                    .ok()
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty()),
            )
        } else {
            let tokens = oauth::login_with_loopback(&Auth0NativeConfig {
                domain: domain.clone(),
                client_id: client_id.clone(),
                audience: audience.clone(),
                open_browser,
            })
            .await?;
            (tokens.access_token, tokens.refresh_token)
        };

        self.persist_session(
            hub_url,
            &access,
            refresh.as_deref(),
            Some(&domain),
            Some(&client_id),
            Some(&audience),
        )?;

        let hub = self
            .hub_client()
            .context("hub client missing after auth_login")?;
        let me = hub.me().await.context("GET /v1/me after Auth0 login")?;
        if me.is_onboarded() {
            self.register_local_device(&hub)
                .await
                .context("register device pubkey after login")?;
        }
        let hub_url = self.config.lock().unwrap().hub_url.clone();
        Ok(status_from_me(&hub_url, &me))
    }

    /// Clear Auth0 tokens and hub client; keep hub URL / Auth0 client settings for re-login.
    /// Does not wipe device Keychain identity.
    pub fn auth_logout(&self) -> Result<StatusResult> {
        let mut cfg = self.config.lock().unwrap();
        cfg.access_token = None;
        cfg.refresh_token = None;
        let hub_url = cfg.hub_url.clone();
        let to_save = cfg.clone();
        drop(cfg);

        let path = self.config_path.clone().unwrap_or_else(config_path);
        save_config_at(&path, &to_save)?;

        *self.hub.lock().unwrap() = None;
        *self.draft.lock().unwrap() = MutandeBundle::default();
        *self.draft_id.lock().unwrap() = None;
        self.processed_threads.lock().unwrap().clear();
        *self.connected_agent_slug.lock().unwrap() = None;

        Ok(StatusResult {
            configured: false,
            signed_in: false,
            needs_onboarding: false,
            hub_url,
            handle: None,
            org_id: None,
            email: None,
            connected_agent: None,
            default_agent: None,
        })
    }

    /// Create org for signed-in Auth0 user, then register device.
    pub async fn create_org(
        &self,
        slug: &str,
        name: Option<&str>,
        handle: Option<&str>,
    ) -> Result<OnboardResult> {
        let slug = slug.trim();
        if slug.is_empty() {
            bail!("missing param: slug");
        }
        let hub = self.hub_client().context("not signed in — call auth_login first")?;
        let me = hub
            .create_org(slug, name.map(str::trim).filter(|s| !s.is_empty()), handle.map(str::trim).filter(|s| !s.is_empty()))
            .await?;
        self.register_local_device(&hub)
            .await
            .context("register device pubkey after create_org")?;
        onboard_from_me(&me)
    }

    /// Join org via invite for signed-in Auth0 user, then register device.
    pub async fn join_org(
        &self,
        invite_code: &str,
        handle: Option<&str>,
    ) -> Result<OnboardResult> {
        let invite_code = invite_code.trim();
        if invite_code.is_empty() {
            bail!("missing param: invite_code");
        }
        let hub = self.hub_client().context("not signed in — call auth_login first")?;
        let me = hub
            .join_org(
                invite_code,
                handle.map(str::trim).filter(|s| !s.is_empty()),
            )
            .await?;
        self.register_local_device(&hub)
            .await
            .context("register device pubkey after join_org")?;
        onboard_from_me(&me)
    }

    async fn register_local_device(&self, hub: &HubClient) -> Result<()> {
        let pubkey = self.device_public()?;
        let agent_slug = self.connected_agent_slug.lock().unwrap().clone();
        hub.register_device(&pubkey, super::device_platform(), agent_slug.as_deref())
            .await?;
        Ok(())
    }

    /// Publish this device pubkey to the hub when signed in + onboarded.
    /// Soft-fails (logs) so status/bootstrap stay usable offline; hard paths
    /// (login / create / join) call [`register_local_device`] directly.
    pub async fn ensure_device_registered(&self) -> Result<()> {
        let Some(hub) = self.hub_client() else {
            return Ok(());
        };
        let me = hub.me().await.context("GET /v1/me before device register")?;
        if !me.is_onboarded() {
            return Ok(());
        }
        self.register_local_device(&hub).await
    }

    pub fn connected_agent_slug(&self) -> Option<String> {
        self.connected_agent_slug.lock().unwrap().clone()
    }

    pub async fn register_connected_agent(&self, slug: &str) -> Result<Agent> {
        let slug = slug.trim();
        if slug.is_empty() {
            bail!("missing param: slug");
        }
        let hub = self.hub_client().context("hub not configured")?;
        let agent = hub.register_agent(slug).await?;
        *self.connected_agent_slug.lock().unwrap() = Some(agent.slug.clone());
        Ok(agent)
    }

    pub async fn list_agents(&self) -> Result<crate::hub_client::AgentListResponse> {
        let hub = self.hub_client().context("hub not configured")?;
        hub.list_agents().await
    }

    pub async fn list_agents_for_handle(&self, handle: &str) -> Result<Vec<Agent>> {
        let hub = self.hub_client().context("hub not configured")?;
        hub.list_agents_for_handle(handle).await
    }

    pub async fn set_default_agent(&self, agent_id: &str) -> Result<Agent> {
        let hub = self.hub_client().context("hub not configured")?;
        hub.set_default_agent(agent_id).await
    }

    pub async fn rename_agent(&self, agent_id: &str, slug: &str) -> Result<Agent> {
        let hub = self.hub_client().context("hub not configured")?;
        hub.rename_agent(agent_id, slug).await
    }

    pub async fn get_router(&self) -> Result<crate::hub_client::RouterConfig> {
        let hub = self.hub_client().context("hub not configured")?;
        hub.get_router().await
    }

    pub async fn set_router(
        &self,
        default_agent_id: Option<&str>,
        rules: Option<Vec<crate::hub_client::RoutingRule>>,
    ) -> Result<crate::hub_client::RouterConfig> {
        let hub = self.hub_client().context("hub not configured")?;
        hub.set_router(default_agent_id, rules).await
    }

    async fn default_agent_slug(&self) -> Option<String> {
        if let Some(hub) = self.hub_client() {
            if let Ok(list) = hub.list_agents().await {
                if let Some(id) = list.default_agent_id.as_deref() {
                    if let Some(agent) = list.agents.iter().find(|a| a.id == id) {
                        return Some(agent.slug.clone());
                    }
                }
            }
        }
        None
    }

    /// Prefer per-request MCP `agent_slug` over the shared connected slot
    /// (multiple hosts overwrite that slot on register_agent).
    fn resolve_send_agent_slug(&self, override_slug: Option<&str>) -> Option<String> {
        if let Some(s) = override_slug.map(str::trim).filter(|s| !s.is_empty()) {
            return Some(s.to_string());
        }
        self.connected_agent_slug()
    }

    async fn effective_agent_slug(&self, override_slug: Option<&str>) -> Option<String> {
        if let Some(s) = self.resolve_send_agent_slug(override_slug) {
            return Some(s);
        }
        self.default_agent_slug().await
    }

    async fn filter_threads_for_agent(
        &self,
        threads: Vec<ThreadMeta>,
        agent_slug: Option<&str>,
    ) -> Result<Vec<ThreadMeta>> {
        // Only scope when the caller names an agent (MCP injects MUTANDE_AGENT_SLUG).
        // Mac UI / bare RPC omit it and must see the full inbox — never fall back to
        // connected_agent_slug (last host to register would hide everyone else's mail).
        let Some(slug) = agent_slug.map(str::trim).filter(|s| !s.is_empty()) else {
            return Ok(threads);
        };
        let Some(hub) = self.hub_client() else {
            return Ok(threads);
        };
        let me = hub.me().await?;
        let user_id = me.user.as_ref().map(|u| u.id.as_str()).unwrap_or("");
        let default_slug = self.default_agent_slug().await;
        let default_slug = default_slug.as_deref().unwrap_or(slug);
        Ok(threads
            .into_iter()
            .filter(|t| thread_visible_for_agent(t, user_id, slug, default_slug))
            .collect())
    }

    fn from_agent_for_send(&self, override_slug: Option<&str>) -> Option<String> {
        self.resolve_send_agent_slug(override_slug)
    }

    fn persist_session(
        &self,
        hub_url: &str,
        access_token: &str,
        refresh_token: Option<&str>,
        auth0_domain: Option<&str>,
        auth0_client_id: Option<&str>,
        auth0_audience: Option<&str>,
    ) -> Result<()> {
        let mut cfg = self.config.lock().unwrap();
        cfg.hub_url = Some(hub_url.to_string());
        cfg.access_token = Some(access_token.to_string());
        if let Some(rt) = refresh_token {
            cfg.refresh_token = Some(rt.to_string());
        }
        if let Some(d) = auth0_domain {
            cfg.auth0_domain = Some(d.to_string());
        }
        if let Some(c) = auth0_client_id {
            cfg.auth0_client_id = Some(c.to_string());
        }
        if let Some(a) = auth0_audience {
            cfg.auth0_audience = Some(a.to_string());
        }
        let to_save = cfg.clone();
        drop(cfg);

        let path = self.config_path.clone().unwrap_or_else(config_path);
        save_config_at(&path, &to_save)?;

        let hub = make_hub_client(
            hub_url,
            access_token,
            to_save.refresh_token.clone(),
            to_save.auth0_domain.clone(),
            to_save.auth0_client_id.clone(),
            Arc::clone(&self.config),
            self.config_path.clone(),
        )?;
        *self.hub.lock().unwrap() = Some(hub);
        Ok(())
    }

    /// Session status from local tokens + hub `/me` when reachable.
    ///
    /// Hub `/me` failures must not look like `needs_onboarding` — that wrongly
    /// sends already-onboarded users (e.g. joined on web) through create/join.
    /// Flutter treats RPC errors as transport issues, not onboarding.
    pub async fn get_status(&self) -> Result<StatusResult> {
        let cfg = self.config.lock().unwrap().clone();
        let signed_in = cfg.hub_url.is_some() && cfg.access_token.is_some();
        if !signed_in {
            return Ok(StatusResult {
                configured: false,
                signed_in: false,
                needs_onboarding: false,
                hub_url: cfg.hub_url,
                handle: None,
                org_id: None,
                email: None,
                connected_agent: None,
                default_agent: None,
            });
        }

        let hub = self
            .hub_client()
            .context("signed in but hub client missing")?;
        let me = hub.me().await.context("GET /v1/me for status")?;
        if me.is_onboarded() {
            // App open / status poll: re-publish pubkey so teammates can always seal replies.
            if let Err(err) = self.register_local_device(&hub).await {
                tracing::warn!(error = %err, "device pubkey register on get_status failed");
            }
        }
        let mut status = status_from_me(&cfg.hub_url, &me);
        status.connected_agent = self.connected_agent_slug();
        status.default_agent = self.default_agent_slug().await;
        Ok(status)
    }

    pub fn device_public(&self) -> Result<DevicePubKey> {
        self.identity.device_public().map_err(|e| anyhow::anyhow!("{e}"))
    }

    pub fn load_secret(&self) -> Result<DeviceSecretKey> {
        self.identity.load_device_secret().map_err(|e| anyhow::anyhow!("{e}"))
    }

    pub fn seal_to_self(&self, plaintext: &[u8]) -> Result<Envelope> {
        let pk = self.device_public()?;
        seal(plaintext, &[pk]).map_err(|e| anyhow::anyhow!("{e}"))
    }

    pub fn open_envelope(&self, envelope: &Envelope) -> Result<Vec<u8>> {
        let sk = self.load_secret()?;
        open(envelope, &sk).map_err(|e| anyhow::anyhow!("{e}"))
    }

    pub async fn sync_draft_from_hub(&self) -> Result<()> {
        let Some(hub) = self.hub_client() else {
            return Ok(());
        };
        if let Some(draft) = hub.primary_draft().await? {
            *self.draft_id.lock().unwrap() = Some(draft.id.clone());
            let plain = self.open_envelope(&draft.envelope)?;
            let bundle: MutandeBundle = serde_json::from_slice(&plain).context("decode draft bundle")?;
            *self.draft.lock().unwrap() = bundle;
        }
        Ok(())
    }

    pub async fn persist_draft(&self) -> Result<()> {
        let bundle = self.draft.lock().unwrap().clone();
        let plain = serde_json::to_vec(&bundle)?;
        let env = self.seal_to_self(&plain)?;

        if let Some(hub) = self.hub_client() {
            let saved = hub.upsert_primary_draft(&env).await?;
            *self.draft_id.lock().unwrap() = Some(saved.id);
        }
        Ok(())
    }

    pub fn get_draft_plain(&self) -> MutandeBundle {
        self.draft.lock().unwrap().clone()
    }

    pub fn set_draft_notes(&self, notes: &str) {
        let mut draft = self.draft.lock().unwrap();
        draft.notes = Some(notes.to_string());
    }

    pub fn merge_question(&self, decision: HumanDecision) {
        let mut draft = self.draft.lock().unwrap();
        draft.questions.retain(|q| q.id != decision.id);
        draft.questions.push(decision);
    }

    pub fn merge_resource_request(&self, req: ResourceRequest) {
        let mut draft = self.draft.lock().unwrap();
        draft.resource_requests.retain(|r| r.id != req.id);
        draft.resource_requests.push(req);
    }

    pub fn clear_draft(&self) {
        *self.draft.lock().unwrap() = MutandeBundle::default();
        *self.draft_id.lock().unwrap() = None;
    }

    pub async fn list_contacts(&self) -> Result<Vec<Contact>> {
        if let Some(hub) = self.hub_client() {
            return hub.list_contacts().await;
        }
        Ok(vec![])
    }

    pub async fn submit_feedback(
        &self,
        message: &str,
        category: Option<&str>,
        app_version: Option<&str>,
    ) -> Result<crate::hub_client::Feedback> {
        let hub = self
            .hub_client()
            .context("not signed in — call auth_login first")?;
        hub.submit_feedback(message, category, app_version, Some(super::device_platform()))
            .await
    }

    pub async fn list_threads(
        &self,
        filter: Option<ThreadFilter>,
        agent_slug: Option<&str>,
    ) -> Result<Vec<ThreadMeta>> {
        if let Some(hub) = self.hub_client() {
            let agent = agent_slug.map(str::trim).filter(|s| !s.is_empty());

            // Hub your_status is user-scoped (outbound self-collab → Waiting).
            // Agent MCP needs audience-ball pending, so merge open + needs_action
            // then remap before filtering.
            let mut threads = if matches!(filter, Some(ThreadFilter::NeedsAction)) && agent.is_some()
            {
                let mut merged = hub.list_threads(Some(ThreadFilter::NeedsAction)).await?;
                for t in hub.list_threads(Some(ThreadFilter::Open)).await? {
                    if !merged.iter().any(|p| p.id == t.id) {
                        merged.push(t);
                    }
                }
                merged
            } else {
                hub.list_threads(filter).await?
            };

            threads = self.filter_threads_for_agent(threads, agent_slug).await?;

            if let Some(slug) = agent {
                let me = hub.me().await?;
                let user_id = me.user.as_ref().map(|u| u.id.as_str()).unwrap_or("");
                let default_slug = self.default_agent_slug().await;
                let default_slug = default_slug.as_deref().unwrap_or(slug);
                for t in &mut threads {
                    t.your_status = Some(agent_your_status(t, user_id, slug, default_slug));
                }
                if matches!(filter, Some(ThreadFilter::NeedsAction)) {
                    threads.retain(|t| {
                        t.status == ThreadStatus::Open
                            && t.your_status == Some(YourStatus::Pending)
                    });
                }
            } else {
                // Mac UI: Needs you = unanswered human decisions only
                // (approval / verify / questions to the bare human handle).
                // Agent-to-agent waiting is never Needs you.
                // Also attach last-message author + preview (local open only).
                for t in &mut threads {
                    match self.fetch_and_open_thread(&t.id).await {
                        Ok(detail) => {
                            apply_last_message_snippet(t, &detail);
                            if t.status == ThreadStatus::Open {
                                t.your_status = Some(if thread_needs_human(&detail) {
                                    YourStatus::Pending
                                } else {
                                    YourStatus::Replied
                                });
                            }
                        }
                        Err(_) => {
                            if t.status == ThreadStatus::Open {
                                t.your_status = Some(YourStatus::Replied);
                            }
                        }
                    }
                }
                if matches!(filter, Some(ThreadFilter::NeedsAction)) {
                    threads.retain(|t| {
                        t.status == ThreadStatus::Open
                            && t.your_status == Some(YourStatus::Pending)
                    });
                }
            }

            // Health pings: auto-pong on inbox poll so hosts don't need an LLM turn.
            if matches!(filter, Some(ThreadFilter::NeedsAction)) {
                for t in &threads {
                    if let Ok(detail) = self.fetch_and_open_thread(&t.id).await {
                        let _ = self.maybe_auto_pong_health(&detail).await;
                    }
                }
            }
            return Ok(threads);
        }
        Ok(vec![])
    }

    async fn fetch_and_open_thread(&self, thread_id: &str) -> Result<OpenedThreadDetail> {
        let Some(hub) = self.hub_client() else {
            bail!("hub not configured");
        };
        let detail = hub.get_thread(thread_id).await?;
        Ok(self.open_thread_detail_async(detail).await)
    }

    pub async fn get_thread(
        &self,
        thread_id: &str,
        agent_slug: Option<&str>,
    ) -> Result<OpenedThreadDetail> {
        let mut detail = self.fetch_and_open_thread(thread_id).await?;
        if self.maybe_auto_pong_health(&detail).await? {
            detail = self.fetch_and_open_thread(thread_id).await?;
        }
        if detail.thread.status != ThreadStatus::Open {
            return Ok(detail);
        }
        if let Some(slug) = agent_slug.map(str::trim).filter(|s| !s.is_empty()) {
            let user_id = if let Some(hub) = self.hub_client() {
                hub.me()
                    .await
                    .ok()
                    .and_then(|me| me.user.map(|u| u.id))
                    .unwrap_or_default()
            } else {
                String::new()
            };
            let default_slug = self.default_agent_slug().await;
            let default_slug = default_slug.as_deref().unwrap_or(slug);
            detail.thread.your_status = Some(agent_your_status(
                &detail.thread,
                &user_id,
                slug,
                default_slug,
            ));
        } else {
            // Mac / human: Needs you only for outstanding human decisions.
            detail.thread.your_status = Some(if thread_needs_human(&detail) {
                YourStatus::Pending
            } else {
                YourStatus::Replied
            });
        }
        Ok(detail)
    }

    /// Auto-reply to health pings (daemon-side). Thread pings stay for agents.
    async fn maybe_auto_pong_health(&self, detail: &OpenedThreadDetail) -> Result<bool> {
        if self.is_processed(&detail.thread.id) {
            return Ok(false);
        }
        let Some(root) = detail
            .messages
            .iter()
            .find(|m| m.parent_message_id.is_none())
        else {
            return Ok(false);
        };
        let Some(bundle) = root.bundle.as_ref() else {
            return Ok(false);
        };
        if bundle.ping_kind != Some(PingKind::Health) {
            return Ok(false);
        }
        // Already has a reply — nothing to do.
        if detail.messages.len() > 1 {
            return Ok(false);
        }
        let pong = MutandeBundle {
            subject: Some("Pong".into()),
            notes: Some("auto".into()),
            ping_kind: Some(PingKind::Health),
            in_reply_to: Some(root.id.clone()),
            ..Default::default()
        };
        self.reply_to_opened_thread(&detail.thread.id, detail, pong, None, None)
            .await?;
        self.mark_processed(&detail.thread.id);
        Ok(true)
    }

    /// Attempt to open each message envelope; succeed with `bundle`, else `open_error` + meta only
    /// (never return ciphertext/wraps into agent/MCP context).
    pub fn open_thread_detail(&self, detail: ThreadDetail) -> OpenedThreadDetail {
        let messages = detail
            .messages
            .into_iter()
            .map(|msg| self.open_thread_message_sync(msg))
            .collect();
        OpenedThreadDetail {
            thread: detail.thread,
            messages,
        }
    }

    async fn open_thread_detail_async(&self, detail: ThreadDetail) -> OpenedThreadDetail {
        let mut messages = Vec::with_capacity(detail.messages.len());
        for msg in detail.messages {
            messages.push(self.open_thread_message_async(msg).await);
        }
        OpenedThreadDetail {
            thread: detail.thread,
            messages,
        }
    }

    fn open_thread_message_sync(&self, msg: ThreadMessage) -> OpenedThreadMessage {
        let plain = self.open_envelope(&msg.envelope);
        self.finish_opened_message(msg, plain)
    }

    async fn open_thread_message_async(&self, msg: ThreadMessage) -> OpenedThreadMessage {
        let plain = self.open_envelope_maybe_blob(&msg.envelope).await;
        self.finish_opened_message(msg, plain)
    }

    fn finish_opened_message(
        &self,
        msg: ThreadMessage,
        plain: Result<Vec<u8>>,
    ) -> OpenedThreadMessage {
        let is_blob = msg.envelope.blob_id.is_some();
        let parent_message_id = msg.parent_message_id.clone();
        let upvotes = msg.upvotes.clone();
        let meta = |open_error: Option<String>| OpenedThreadMessage {
            id: msg.id.clone(),
            thread_id: msg.thread_id.clone(),
            from_user_id: msg.from_user_id.clone(),
            from_handle: msg.from_handle.clone(),
            created_at: msg.created_at.clone(),
            sender_only: msg.sender_only,
            parent_message_id: parent_message_id.clone(),
            bundle: None,
            envelope: None,
            open_error,
            upvotes: upvotes.clone(),
        };

        let mut opened = match plain {
            Ok(plain) => match serde_json::from_slice::<MutandeBundle>(&plain) {
                Ok(bundle) => OpenedThreadMessage {
                    id: msg.id,
                    thread_id: msg.thread_id,
                    from_user_id: msg.from_user_id,
                    from_handle: msg.from_handle,
                    created_at: msg.created_at,
                    sender_only: msg.sender_only,
                    parent_message_id: parent_message_id.clone(),
                    bundle: Some(bundle),
                    envelope: None,
                    open_error: None,
                    upvotes: upvotes.clone(),
                },
                Err(_err) if is_blob => {
                    // Legacy/raw blob plaintext (not a MutandeBundle). Inline small
                    // UTF-8 so agents can read .md/.txt; stub binary/large.
                    OpenedThreadMessage {
                        id: msg.id,
                        thread_id: msg.thread_id,
                        from_user_id: msg.from_user_id,
                        from_handle: msg.from_handle,
                        created_at: msg.created_at,
                        sender_only: msg.sender_only,
                        parent_message_id: parent_message_id.clone(),
                        bundle: Some(bundle_from_raw_blob_plaintext(&plain)),
                        envelope: None,
                        open_error: None,
                        upvotes: upvotes.clone(),
                    }
                }
                Err(err) => meta(Some(format!("decode bundle: {err}"))),
            },
            Err(err) => meta(Some(err.to_string())),
        };
        if opened.parent_message_id.is_none() {
            if let Some(ref bundle) = opened.bundle {
                opened.parent_message_id = bundle.in_reply_to.clone();
            }
        }
        opened
    }

    /// Open inline envelope, or download R2 ciphertext when `blob_id` is set.
    pub async fn open_envelope_maybe_blob(&self, envelope: &Envelope) -> Result<Vec<u8>> {
        if let Some(blob_id) = envelope.blob_id.as_deref() {
            let Some(hub) = self.hub_client() else {
                bail!("hub not configured (needed for blob download)");
            };
            let dl = hub.blob_download_url(blob_id).await?;
            let ciphertext = hub.get_presigned(&dl.download_url).await?;
            let sk = self.load_secret()?;
            return open_from_bytes(envelope, &ciphertext, &sk)
                .map_err(|e| anyhow::anyhow!("{e}"));
        }
        self.open_envelope(envelope)
    }

    /// Seal plaintext to temp → hub upload-url → PUT → envelope with blob_id.
    pub async fn seal_and_upload_blob(
        &self,
        plaintext: &[u8],
        recipients: &[DevicePubKey],
    ) -> Result<Envelope> {
        let Some(hub) = self.hub_client() else {
            bail!("hub not configured");
        };
        let sealed =
            seal_to_temp(plaintext, recipients).map_err(|e| anyhow::anyhow!("{e}"))?;
        let upload = hub
            .blob_upload_url(sealed.size_bytes, Some("application/octet-stream"))
            .await?;
        let bytes = fs::read(&sealed.ciphertext_path)
            .with_context(|| format!("read {}", sealed.ciphertext_path.display()))?;
        hub.put_presigned(&upload.upload_url, &bytes).await?;
        let env = with_blob_id(sealed.envelope, upload.blob_id);
        let _ = fs::remove_file(&sealed.ciphertext_path);
        Ok(env)
    }

    /// Create one hub thread per expanded recipient. Bare `@all` expands to a
    /// single `@all` group thread. `thread_ids[i]` matches `recipients[i]`;
    /// callers expose `thread_id` = first id.
    pub async fn forward_draft(
        &self,
        recipient: &str,
        agent_slug: Option<&str>,
    ) -> Result<ForwardThreadsResult> {
        let bundle = self.get_draft_plain();
        if bundle_is_empty(&bundle) {
            bail!("draft is empty");
        }

        self.assert_recipient_allowed(recipient, agent_slug).await?;
        let plain = serde_json::to_vec(&bundle)?;
        let seal_keys = self.resolve_recipient_pubkeys(recipient).await?;
        let env = self.seal_inline_or_blob(&plain, &seal_keys).await?;

        let result = if let Some(hub) = self.hub_client() {
            let hub_tos = self.expand_hub_recipients(recipient, agent_slug).await?;
            let from_agent = self.from_agent_for_send(agent_slug);
            let mut thread_ids = Vec::with_capacity(hub_tos.len());
            for to in &hub_tos {
                let resp = hub
                    .create_thread(to, &env, from_agent.as_deref())
                    .await?;
                thread_ids.push(resp.thread.id);
            }
            if thread_ids.is_empty() {
                bail!("no hub recipients after expand");
            }
            ForwardThreadsResult {
                recipients: hub_tos,
                thread_ids,
            }
        } else {
            ForwardThreadsResult {
                recipients: vec![recipient.to_string()],
                thread_ids: vec![uuid::Uuid::new_v4().to_string()],
            }
        };

        let draft_id = self.draft_id.lock().unwrap().take();
        if let Some(hub) = self.hub_client() {
            if let Some(draft_id) = draft_id {
                let _ = hub.delete_draft(&draft_id).await;
            }
        }
        self.clear_draft();

        Ok(result)
    }

    /// Explicit blob send: seal bytes → upload → create thread with blob envelope.
    ///
    /// Seals raw `plaintext` (artifact bytes). Recipient `get_thread` opens and
    /// surfaces a summary bundle (size/name) without inlining ciphertext.
    pub async fn forward_blob(
        &self,
        recipient: &str,
        plaintext: &[u8],
        subject: Option<&str>,
        filename: Option<&str>,
        agent_slug: Option<&str>,
    ) -> Result<ForwardThreadsResult> {
        if plaintext.is_empty() {
            bail!("blob plaintext empty");
        }
        self.assert_recipient_allowed(recipient, agent_slug).await?;
        let seal_keys = self.resolve_recipient_pubkeys(recipient).await?;
        // Wrap artifact in a bundle so open yields subject/name/mime/content for agents.
        let bundle = bundle_for_blob_artifact(plaintext, subject, filename);
        let plain = serde_json::to_vec(&bundle).context("serialize blob bundle")?;
        let env = self.seal_and_upload_blob(&plain, &seal_keys).await?;

        if let Some(hub) = self.hub_client() {
            let hub_tos = self.expand_hub_recipients(recipient, agent_slug).await?;
            let from_agent = self.from_agent_for_send(agent_slug);
            let mut thread_ids = Vec::with_capacity(hub_tos.len());
            for to in &hub_tos {
                let resp = hub
                    .create_thread(to, &env, from_agent.as_deref())
                    .await?;
                thread_ids.push(resp.thread.id);
            }
            if thread_ids.is_empty() {
                bail!("no hub recipients after expand");
            }
            Ok(ForwardThreadsResult {
                recipients: hub_tos,
                thread_ids,
            })
        } else {
            Ok(ForwardThreadsResult {
                recipients: vec![recipient.to_string()],
                thread_ids: vec![uuid::Uuid::new_v4().to_string()],
            })
        }
    }

    async fn seal_inline_or_blob(
        &self,
        plain: &[u8],
        recipients: &[DevicePubKey],
    ) -> Result<Envelope> {
        if plain.len() > Self::INLINE_COMFORT_ZONE && self.hub_client().is_some() {
            self.seal_and_upload_blob(plain, recipients).await
        } else {
            seal(plain, recipients).map_err(|e| anyhow::anyhow!("{e}"))
        }
    }

    pub async fn reply_to_thread(
        &self,
        thread_id: &str,
        bundle: MutandeBundle,
        to_agent: Option<&str>,
        agent_slug: Option<&str>,
    ) -> Result<()> {
        if bundle_is_empty(&bundle) {
            bail!(
                "reply bundle is empty — put the answer in bundle.notes (and optional subject), \
                 not only in chat. Example: {{\"notes\":\"…\"}}"
            );
        }
        // Fetch without auto-pong to avoid re-entry when health pings reply.
        let detail = self.fetch_and_open_thread(thread_id).await?;
        self.reply_to_opened_thread(thread_id, &detail, bundle, to_agent, agent_slug)
            .await
    }

    async fn reply_to_opened_thread(
        &self,
        thread_id: &str,
        detail: &OpenedThreadDetail,
        bundle: MutandeBundle,
        to_agent: Option<&str>,
        agent_slug: Option<&str>,
    ) -> Result<()> {
        let plain = serde_json::to_vec(&bundle)?;
        let recipients = self.resolve_reply_recipients(detail).await?;
        let env = self.seal_inline_or_blob(&plain, &recipients).await?;

        if let Some(hub) = self.hub_client() {
            let from_agent = self.from_agent_for_send(agent_slug);
            hub.reply_to_thread(
                thread_id,
                &env,
                from_agent.as_deref(),
                to_agent,
                bundle.in_reply_to.as_deref(),
            )
            .await?;
        }
        Ok(())
    }

    /// Product ping — creates real threads. `health` → daemon auto-pong; `thread` → agent reply.
    /// Solo `@all` (no other agents) falls back to bare-handle inbox for `thread` kind only.
    pub async fn ping(
        &self,
        target: &str,
        kind: PingKind,
        agent_slug: Option<&str>,
    ) -> Result<ForwardThreadsResult> {
        let target = {
            let t = target.trim();
            if t.is_empty() {
                "@all"
            } else {
                t
            }
        };
        let notes = match kind {
            PingKind::Health => "health ping",
            PingKind::Thread => "thread ping — please reply with pong",
        };
        let bundle = MutandeBundle {
            subject: Some("Ping".into()),
            notes: Some(notes.into()),
            ping_kind: Some(kind.clone()),
            ..Default::default()
        };

        self.assert_recipient_allowed(target, agent_slug).await?;
        let plain = serde_json::to_vec(&bundle)?;
        let seal_keys = self.resolve_recipient_pubkeys(target).await?;
        let env = self.seal_inline_or_blob(&plain, &seal_keys).await?;

        let hub_tos = match self.expand_hub_recipients(target, agent_slug).await {
            Ok(tos) => tos,
            Err(err)
                if kind == PingKind::Thread
                    && (is_my_agents_handle(target) || target.eq_ignore_ascii_case("@all")) =>
            {
                // Day-one: only one agent connected — still create a Mac-visible thread.
                let bare = self.my_bare_handle().await?;
                tracing::info!(
                    target = %target,
                    fallback = %bare,
                    "ping @all solo fallback: {err}"
                );
                vec![bare]
            }
            Err(err) => return Err(err),
        };

        if let Some(hub) = self.hub_client() {
            let from_agent = self.from_agent_for_send(agent_slug);
            let mut thread_ids = Vec::with_capacity(hub_tos.len());
            for to in &hub_tos {
                let resp = hub
                    .create_thread(to, &env, from_agent.as_deref())
                    .await?;
                thread_ids.push(resp.thread.id);
            }
            if thread_ids.is_empty() {
                bail!("ping produced no threads");
            }
            Ok(ForwardThreadsResult {
                recipients: hub_tos,
                thread_ids,
            })
        } else {
            Ok(ForwardThreadsResult {
                recipients: vec![target.to_string()],
                thread_ids: vec![uuid::Uuid::new_v4().to_string()],
            })
        }
    }

    /// Toggle agent upvote on a thread message (coordination weight, not ranking).
    pub async fn toggle_message_upvote(
        &self,
        thread_id: &str,
        message_id: &str,
        agent_slug: Option<&str>,
    ) -> Result<crate::hub_client::ToggleUpvoteResponse> {
        let Some(hub) = self.hub_client() else {
            bail!("hub not configured");
        };
        let slug = self.effective_agent_slug(agent_slug).await;
        hub.toggle_message_upvote(thread_id, message_id, slug.as_deref())
            .await
    }

    /// Own device safety number + QR/compare URI.
    pub fn own_safety_number(&self) -> Result<SafetyNumberResult> {
        let pk = self.device_public()?;
        let fingerprint = safety_number(&pk);
        let uri = safety_uri("me", &pk);
        Ok(SafetyNumberResult {
            handle: "me".into(),
            fingerprint,
            uri,
            verified: None,
        })
    }

    /// Lookup contact pubkey → safety number for compare / QR stub.
    pub async fn contact_safety_number(&self, handle: &str) -> Result<SafetyNumberResult> {
        let handle = handle.trim();
        if handle.is_empty() {
            bail!("missing param: handle");
        }
        let handle = strip_agent_suffix(handle);
        let contacts = self.list_contacts().await?;
        for c in &contacts {
            if c.handle == handle {
                let Some(pk) = c.pubkey.as_deref().and_then(pubkey_from_hub_string) else {
                    bail!("contact {handle} has no pubkey");
                };
                let fingerprint = safety_number(&pk);
                return Ok(SafetyNumberResult {
                    handle: handle.to_string(),
                    fingerprint: fingerprint.clone(),
                    uri: safety_uri(handle, &pk),
                    verified: None,
                });
            }
        }
        if let Some(hub) = self.hub_client() {
            if let Ok(me) = hub.me().await {
                if me
                    .user
                    .as_ref()
                    .and_then(|u| u.handle.as_deref())
                    == Some(handle)
                {
                    let pk = self.device_public()?;
                    return Ok(SafetyNumberResult {
                        handle: handle.to_string(),
                        fingerprint: safety_number(&pk),
                        uri: safety_uri(handle, &pk),
                        verified: None,
                    });
                }
            }
        }
        bail!("unknown contact {handle}");
    }

    /// Compare a pasted/scanned fingerprint or URI against a contact.
    pub async fn verify_contact(
        &self,
        handle: &str,
        fingerprint_or_uri: &str,
    ) -> Result<SafetyNumberResult> {
        let expected = self.contact_safety_number(handle).await?;
        let candidate = fingerprint_or_uri.trim();
        let candidate_fp = if let Some((uri_handle, fp)) =
            crate::crypto::parse_safety_uri(candidate)
        {
            if uri_handle != handle {
                bail!("URI handle {uri_handle} does not match {handle}");
            }
            fp
        } else {
            candidate.to_string()
        };
        let verified = fingerprints_match(&expected.fingerprint, &candidate_fp);
        Ok(SafetyNumberResult {
            verified: Some(verified),
            ..expected
        })
    }

    pub async fn close_thread(&self, thread_id: &str) -> Result<()> {
        if let Some(hub) = self.hub_client() {
            hub.close_thread(thread_id).await?;
        }
        Ok(())
    }

    pub async fn delete_thread(&self, thread_id: &str) -> Result<()> {
        let hub = self.hub_client().context("hub not configured")?;
        hub.delete_thread(thread_id).await?;
        self.processed_threads.lock().unwrap().remove(thread_id);
        Ok(())
    }

    pub fn mark_processed(&self, thread_id: &str) {
        self.processed_threads.lock().unwrap().insert(thread_id.to_string());
    }

    pub fn is_processed(&self, thread_id: &str) -> bool {
        self.processed_threads.lock().unwrap().contains(thread_id)
    }

    async fn my_bare_handle(&self) -> Result<String> {
        let hub = self.hub_client().context("hub not configured")?;
        let me = hub.me().await?;
        me.user
            .as_ref()
            .and_then(|u| u.handle.as_deref())
            .map(strip_agent_suffix)
            .map(|s| s.to_string())
            .context("local handle unknown — cannot expand self-collaboration address")
    }

    /// Expand `@claude` to `you@org/slug` for hubs that lack shorthand.
    /// Bare `@all` stays `@all` — one shared my-agents group thread on the hub.
    async fn expand_hub_recipients(
        &self,
        recipient: &str,
        agent_slug: Option<&str>,
    ) -> Result<Vec<String>> {
        let trimmed = recipient.trim();
        let parsed = parse_display_address(trimmed)?;
        match parsed.kind {
            AddressKind::SelfAgent => {
                let slug = parsed
                    .agent_slug
                    .as_deref()
                    .context("self-agent shorthand missing slug")?;
                let bare = self.my_bare_handle().await?;
                Ok(vec![format!("{bare}/{slug}")])
            }
            AddressKind::MyAgents => {
                let list = self.list_agents().await?;
                let from = self.effective_agent_slug(agent_slug).await;
                let has_peer = list
                    .agents
                    .iter()
                    .any(|a| from.as_deref() != Some(a.slug.as_str()));
                if !has_peer {
                    bail!(
                        "no other agents to hand off to with @all — register another agent or use @claude/@cursor/@chatgpt"
                    );
                }
                Ok(vec!["@all".into()])
            }
            AddressKind::User | AddressKind::OrgBroadcast => Ok(vec![trimmed.to_string()]),
        }
    }

    /// Reject same-agent self-loops; allow handoffs to a different own agent slot.
    async fn assert_recipient_allowed(
        &self,
        recipient: &str,
        agent_slug: Option<&str>,
    ) -> Result<()> {
        let parsed = parse_display_address(recipient)?;
        match parsed.kind {
            AddressKind::OrgBroadcast | AddressKind::MyAgents => return Ok(()),
            AddressKind::SelfAgent => {
                let from_slug = self
                    .effective_agent_slug(agent_slug)
                    .await
                    .context("connected agent unknown — cannot validate self-handoff")?;
                let to_slug = parsed
                    .agent_slug
                    .as_deref()
                    .context("self-agent shorthand missing slug")?;
                if from_slug == to_slug {
                    bail!(
                        "cannot hand off to the same agent ({from_slug}); send to a different agent address, e.g. @claude"
                    );
                }
                return Ok(());
            }
            AddressKind::User => {}
        }

        let Some(hub) = self.hub_client() else {
            return Ok(());
        };
        let Ok(me) = hub.me().await else {
            // Offline / mock hubs without /me: skip local check; hub still enforces.
            return Ok(());
        };
        let my_bare = me
            .user
            .as_ref()
            .and_then(|u| u.handle.as_deref())
            .map(strip_agent_suffix);
        let target_bare = bare_handle(&parsed.local, &parsed.org_slug);
        if my_bare != Some(target_bare.as_str()) {
            return Ok(());
        }

        let from_slug = self
            .effective_agent_slug(agent_slug)
            .await
            .context("connected agent unknown — cannot validate self-handoff")?;
        let to_slug = match parsed.agent_slug.as_deref() {
            Some(s) => s.to_string(),
            None => self
                .default_agent_slug()
                .await
                .context("default agent unknown — cannot validate bare self-send")?,
        };
        if from_slug == to_slug {
            bail!(
                "cannot hand off to the same agent ({from_slug}); send to a different agent address, e.g. @claude or {target_bare}/claude"
            );
        }
        Ok(())
    }

    async fn resolve_recipient_pubkeys(&self, recipient: &str) -> Result<Vec<DevicePubKey>> {
        let trimmed = recipient.trim();
        let parsed = parse_display_address(trimmed)?;

        // Bare @all (my agents) and @slug (self agent): seal once to own device pubkeys.
        if matches!(parsed.kind, AddressKind::MyAgents | AddressKind::SelfAgent) {
            return Ok(vec![self.device_public()?]);
        }

        let bare = strip_agent_suffix(trimmed);
        if is_broadcast_handle(bare) {
            let contacts = self.list_contacts().await?;
            let others: Vec<&Contact> = contacts
                .iter()
                .filter(|c| !is_broadcast_handle(&c.handle))
                .collect();
            let keys: Vec<DevicePubKey> = others
                .iter()
                .flat_map(|c| contact_device_pubkeys(c))
                .collect();
            if !keys.is_empty() {
                return Ok(keys);
            }
            if others.is_empty() {
                // Sole-member org: list_contacts excludes self, so @all@org has no other
                // keys — encrypt to own device(s) for default-agent inbox delivery.
                return Ok(vec![self.device_public()?]);
            }
            bail!(
                "broadcast {recipient} has no registered pubkeys — no other members have onboarded devices"
            );
        }

        let contacts = self.list_contacts().await?;
        for contact in &contacts {
            if contact.handle == bare {
                let keys = contact_device_pubkeys(contact);
                if !keys.is_empty() {
                    return Ok(keys);
                }
                bail!("contact {bare} has no pubkey");
            }
        }

        if let Some(hub) = self.hub_client() {
            if let Ok(me) = hub.me().await {
                if me
                    .user
                    .as_ref()
                    .and_then(|u| u.handle.as_deref())
                    .map(strip_agent_suffix)
                    == Some(bare)
                {
                    // Self-send / agent handoff: seal to local identity (not in contacts).
                    return Ok(vec![self.device_public()?]);
                }
            }
        }

        bail!("unknown recipient {recipient}");
    }

    /// Seal replies to the original sender's devices.
    ///
    /// Org `@all@org` announcements are sender-only. My-agents `@all` groups seal
    /// to the same user devices so every agent on this Mac can open peer replies.
    /// Direct-thread replies likewise go back to the original sender's devices.
    async fn resolve_reply_recipients(
        &self,
        detail: &OpenedThreadDetail,
    ) -> Result<Vec<DevicePubKey>> {
        let sender = strip_agent_suffix(&detail.thread.from).to_string();
        self.resolve_recipient_pubkeys(&sender).await
    }

}

/// Hub client that persists Auth0 token refreshes into config.json.
fn make_hub_client(
    hub_url: &str,
    access_token: &str,
    refresh_token: Option<String>,
    auth0_domain: Option<String>,
    auth0_client_id: Option<String>,
    config: Arc<Mutex<DaemonConfig>>,
    config_path_override: Option<PathBuf>,
) -> Result<HubClient> {
    let path = config_path_override.unwrap_or_else(config_path);
    let on_tokens = move |new_access: String, new_refresh: Option<String>| {
        if let Ok(mut guard) = config.lock() {
            guard.access_token = Some(new_access);
            if let Some(rt) = new_refresh {
                guard.refresh_token = Some(rt);
            }
            let snapshot = guard.clone();
            drop(guard);
            if let Err(err) = save_config_at(&path, &snapshot) {
                tracing::error!(error = %err, "failed to persist Auth0 tokens");
            }
        }
    };

    HubClient::new(
        crate::hub_client::HubConfig::new(hub_url, access_token)
            .with_refresh_token(refresh_token)
            .with_auth0(auth0_domain, auth0_client_id)
            .with_on_tokens(on_tokens),
    )
}

fn status_from_me(hub_url: &Option<String>, me: &MeResponse) -> StatusResult {
    let onboarded = me.is_onboarded();
    StatusResult {
        configured: onboarded,
        signed_in: true,
        needs_onboarding: !onboarded,
        hub_url: hub_url.clone(),
        handle: me.user.as_ref().and_then(|u| u.handle.clone()),
        org_id: me
            .user
            .as_ref()
            .and_then(|u| u.org_id.clone())
            .or_else(|| me.org.as_ref().map(|o| o.id.clone())),
        email: me
            .email
            .clone()
            .or_else(|| me.user.as_ref().and_then(|u| u.email.clone())),
        connected_agent: None,
        default_agent: None,
    }
}

/// All device pubkeys for a contact (multi-device fan-out), falling back to legacy `pubkey`.
fn contact_device_pubkeys(contact: &Contact) -> Vec<DevicePubKey> {
    let mut keys: Vec<DevicePubKey> = contact
        .devices
        .iter()
        .filter_map(|d| pubkey_from_hub_string(&d.pubkey))
        .collect();
    if keys.is_empty() {
        if let Some(pk) = contact.pubkey.as_deref().and_then(pubkey_from_hub_string) {
            keys.push(pk);
        }
    } else if let Some(pk) = contact.pubkey.as_deref().and_then(pubkey_from_hub_string) {
        if !keys.iter().any(|k| k == &pk) {
            keys.push(pk);
        }
    }
    keys
}

fn agent_matches_display(display: &str, slug: &str, default_slug: &str) -> bool {
    match agent_suffix(display) {
        Some(s) => s == slug,
        None => slug == default_slug,
    }
}

/// Fill `last_from` / `last_subject` / `last_preview` from opened plaintext.
fn apply_last_message_snippet(thread: &mut ThreadMeta, detail: &OpenedThreadDetail) {
    let Some(latest) = detail
        .messages
        .iter()
        .max_by(|a, b| a.created_at.cmp(&b.created_at))
    else {
        return;
    };
    thread.last_from = Some(latest.from_handle.clone());
    thread.last_subject = bundle_subject(latest.bundle.as_ref())
        .or_else(|| {
            // Stable thread title: fall back to the root/OP subject.
            detail
                .messages
                .iter()
                .filter(|m| m.parent_message_id.is_none())
                .min_by(|a, b| a.created_at.cmp(&b.created_at))
                .and_then(|op| bundle_subject(op.bundle.as_ref()))
        })
        .map(|s| truncate_preview(&s, 72));
    thread.last_preview = latest
        .bundle
        .as_ref()
        .and_then(bundle_body_preview)
        .map(|s| truncate_preview(&s, 96));
}

fn bundle_subject(bundle: Option<&MutandeBundle>) -> Option<String> {
    bundle.and_then(|b| {
        b.subject
            .as_ref()
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string())
    })
}

/// Body preview for the list row — notes / question / answer / resource (not subject).
fn bundle_body_preview(b: &MutandeBundle) -> Option<String> {
    if let Some(n) = b.notes.as_ref().map(|n| n.trim()).filter(|n| !n.is_empty()) {
        return Some(n.to_string());
    }
    if let Some(q) = b
        .questions
        .iter()
        .map(|q| q.prompt.trim())
        .find(|p| !p.is_empty())
    {
        return Some(q.to_string());
    }
    if let Some(a) = b
        .answers
        .iter()
        .map(|a| a.answer.trim())
        .find(|a| !a.is_empty())
    {
        return Some(a.to_string());
    }
    b.resource_requests
        .iter()
        .map(|r| r.description.trim())
        .find(|d| !d.is_empty())
        .map(|d| format!("Resource: {d}"))
}

fn truncate_preview(s: &str, max_chars: usize) -> String {
    let collapsed = s.split_whitespace().collect::<Vec<_>>().join(" ");
    if collapsed.chars().count() <= max_chars {
        return collapsed;
    }
    let mut out = collapsed.chars().take(max_chars.saturating_sub(1)).collect::<String>();
    out.push('…');
    out
}

/// True when the thread still needs a human decision (approval / verify /
/// question addressed to the person, not an agent slot).
fn thread_needs_human(detail: &OpenedThreadDetail) -> bool {
    if detail.thread.status != ThreadStatus::Open {
        return false;
    }
    let mut open_ids: HashSet<String> = HashSet::new();
    let mut answered: HashSet<String> = HashSet::new();
    let audience_is_human = human_decision_targets_person(&detail.thread);

    for msg in &detail.messages {
        let Some(bundle) = msg.bundle.as_ref() else {
            continue;
        };
        for q in &bundle.questions {
            if human_decision_kind_needs_you(&q.kind, audience_is_human) {
                open_ids.insert(q.id.clone());
            }
        }
        for a in &bundle.answers {
            answered.insert(a.question_id.clone());
        }
    }
    open_ids.difference(&answered).next().is_some()
}

fn human_decision_kind_needs_you(kind: &str, audience_is_human: bool) -> bool {
    match kind {
        "confirm_forward" | "verify_contact" => true,
        // Freeform questions to a bare handle are for the person; /agent is for agents.
        "question" => audience_is_human,
        _ => false,
    }
}

fn human_decision_targets_person(thread: &ThreadMeta) -> bool {
    match thread.kind {
        ThreadKind::Broadcast => false,
        ThreadKind::Direct => agent_suffix(&thread.audience).is_none(),
    }
}

/// Per-agent inbox status. Hub stores one row per user; self-collab outbound
/// reads as Waiting for the Mac UI. The audience agent still needs action.
fn agent_your_status(
    thread: &ThreadMeta,
    my_user_id: &str,
    slug: &str,
    default_slug: &str,
) -> YourStatus {
    if thread.status != ThreadStatus::Open {
        return thread.your_status.unwrap_or(YourStatus::Replied);
    }

    // Direct: ball is with the audience agent until the first reply.
    if thread.kind == ThreadKind::Direct
        && agent_matches_display(&thread.audience, slug, default_slug)
        && thread.reply_count == 0
    {
        return YourStatus::Pending;
    }

    // Bare @all: every own agent except the sender acts while unreplied.
    if thread.kind == ThreadKind::Broadcast
        && is_my_agents_handle(&thread.audience)
        && thread.from_user_id == my_user_id
        && !agent_matches_display(&thread.from, slug, default_slug)
        && thread.reply_count == 0
    {
        return YourStatus::Pending;
    }

    if thread.from_user_id != my_user_id {
        return thread.your_status.unwrap_or(YourStatus::Pending);
    }

    YourStatus::Replied
}

fn thread_visible_for_agent(
    thread: &ThreadMeta,
    my_user_id: &str,
    slug: &str,
    default_slug: &str,
) -> bool {
    if thread.kind == ThreadKind::Broadcast {
        // Bare @all → all of this user's agents. @all@org → default agent only.
        if is_my_agents_handle(&thread.audience) {
            return thread.from_user_id == my_user_id;
        }
        return slug == default_slug;
    }
    if thread.from_user_id == my_user_id {
        // Outbound: visible to the sending agent.
        if agent_matches_display(&thread.from, slug, default_slug) {
            return true;
        }
        // Self-handoff only: also visible to the target own-agent slot.
        // Do not match on audience slug alone — that would leak e.g.
        // cursor→bob@acme/claude into the sender's own `claude` agent.
        let same_user = strip_agent_suffix(&thread.from) == strip_agent_suffix(&thread.audience);
        same_user && agent_matches_display(&thread.audience, slug, default_slug)
    } else {
        agent_matches_display(&thread.audience, slug, default_slug)
    }
}

fn bundle_is_empty(bundle: &MutandeBundle) -> bool {
    bundle.questions.is_empty()
        && bundle.resource_requests.is_empty()
        && bundle.resources.is_empty()
        && bundle.answers.is_empty()
        && bundle.subject.as_ref().is_none_or(|s| s.trim().is_empty())
        && bundle.context.as_ref().is_none_or(|c| c.trim().is_empty())
        && bundle.notes.as_ref().is_none_or(|n| n.trim().is_empty())
        && bundle.ping_kind.is_none()
}

/// Max raw-blob UTF-8 bytes to inline into an opened bundle for agents.
const RAW_BLOB_INLINE_MAX: usize = 256 * 1024;

fn guess_blob_mime(name: &str) -> &'static str {
    match std::path::Path::new(name)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())
        .as_deref()
    {
        Some("md") | Some("markdown") => "text/markdown",
        Some("txt") | Some("text") => "text/plain",
        Some("json") => "application/json",
        Some("csv") => "text/csv",
        Some("html") | Some("htm") => "text/html",
        Some("rs") | Some("ts") | Some("tsx") | Some("js") | Some("jsx") | Some("py")
        | Some("toml") | Some("yaml") | Some("yml") => "text/plain",
        Some("png") => "image/png",
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        Some("pdf") => "application/pdf",
        Some("zip") => "application/zip",
        _ => "application/octet-stream",
    }
}

/// Build the sealed plaintext for `forward_blob`: a MutandeBundle carrying the artifact.
fn bundle_for_blob_artifact(
    plaintext: &[u8],
    subject: Option<&str>,
    filename: Option<&str>,
) -> MutandeBundle {
    let name = filename
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or("artifact.bin")
        .to_string();
    let mime = guess_blob_mime(&name).to_string();
    let (content, notes) = if let Ok(text) = std::str::from_utf8(plaintext) {
        (Some(text.to_string()), None)
    } else if plaintext.len() <= RAW_BLOB_INLINE_MAX {
        use base64::Engine;
        (
            Some(base64::engine::general_purpose::STANDARD.encode(plaintext)),
            Some(format!(
                "Binary artifact ({} bytes); resource.content is standard base64.",
                plaintext.len()
            )),
        )
    } else {
        (
            None,
            Some(format!(
                "Binary artifact ({} bytes); too large to inline in opened bundle.",
                plaintext.len()
            )),
        )
    };
    MutandeBundle {
        subject: subject
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string)
            .or_else(|| Some(name.clone())),
        notes,
        resources: vec![BundleResource {
            name,
            mime,
            content,
        }],
        ..Default::default()
    }
}

/// Legacy raw blob plaintext → agent-readable bundle (UTF-8 inline when small).
fn bundle_from_raw_blob_plaintext(plain: &[u8]) -> MutandeBundle {
    if plain.len() <= RAW_BLOB_INLINE_MAX {
        if let Ok(text) = std::str::from_utf8(plain) {
            let name = if text.trim_start().starts_with('#') {
                "artifact.md"
            } else {
                "artifact.txt"
            };
            let mime = guess_blob_mime(name).to_string();
            return MutandeBundle {
                subject: Some("blob artifact".into()),
                notes: Some(text.to_string()),
                resources: vec![BundleResource {
                    name: name.into(),
                    mime,
                    content: Some(text.to_string()),
                }],
                ..Default::default()
            };
        }
    }
    MutandeBundle {
        subject: Some("blob artifact".into()),
        notes: Some(format!(
            "Opened encrypted blob ({} bytes); content not inlined (binary or too large).",
            plain.len()
        )),
        resources: vec![BundleResource {
            name: "artifact.bin".into(),
            mime: "application/octet-stream".into(),
            content: None,
        }],
        ..Default::default()
    }
}

fn onboard_from_me(me: &MeResponse) -> Result<OnboardResult> {
    let user = me.user.as_ref().context("onboarding response missing user")?;
    let handle = user
        .handle
        .clone()
        .context("onboarding response missing handle")?;
    let org_id = user
        .org_id
        .clone()
        .or_else(|| me.org.as_ref().map(|o| o.id.clone()))
        .context("onboarding response missing org_id")?;
    Ok(OnboardResult { handle, org_id })
}

fn resolve_auth0_domain(explicit: Option<&str>) -> Result<String> {
    if let Some(d) = explicit.map(str::trim).filter(|s| !s.is_empty()) {
        return Ok(d.to_string());
    }
    if let Ok(d) = std::env::var("AUTH0_DOMAIN") {
        let d = d.trim().to_string();
        if !d.is_empty() {
            return Ok(d);
        }
    }
    Ok(super::auth0_defaults::AUTH0_DOMAIN.to_string())
}

fn resolve_auth0_client_id(explicit: Option<&str>) -> Result<String> {
    if let Some(c) = explicit.map(str::trim).filter(|s| !s.is_empty()) {
        return Ok(c.to_string());
    }
    for key in ["AUTH0_NATIVE_CLIENT_ID", "AUTH0_CLIENT_ID"] {
        if let Ok(c) = std::env::var(key) {
            let c = c.trim().to_string();
            if !c.is_empty() {
                return Ok(c);
            }
        }
    }
    Ok(super::auth0_defaults::AUTH0_NATIVE_CLIENT_ID.to_string())
}

fn resolve_auth0_audience(explicit: Option<&str>) -> String {
    if let Some(a) = explicit.map(str::trim).filter(|s| !s.is_empty()) {
        return a.to_string();
    }
    std::env::var("AUTH0_AUDIENCE")
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| super::auth0_defaults::AUTH0_AUDIENCE.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hub_client::{ThreadKind, ThreadStatus, YourStatus};

    #[test]
    fn auth0_resolvers_prefer_explicit_params() {
        assert_eq!(
            resolve_auth0_domain(Some("custom.auth0.com")).unwrap(),
            "custom.auth0.com"
        );
        assert_eq!(
            resolve_auth0_client_id(Some("custom-client")).unwrap(),
            "custom-client"
        );
        assert_eq!(
            resolve_auth0_audience(Some("https://custom.audience")),
            "https://custom.audience"
        );
    }

    #[test]
    fn auth0_resolvers_fall_back_to_builtin_defaults_when_env_unset() {
        // Skip assertions for any AUTH0_* already present (CI / local .env).
        if std::env::var("AUTH0_DOMAIN").is_err() {
            assert_eq!(
                resolve_auth0_domain(None).unwrap(),
                super::super::auth0_defaults::AUTH0_DOMAIN
            );
        }
        if std::env::var("AUTH0_NATIVE_CLIENT_ID").is_err()
            && std::env::var("AUTH0_CLIENT_ID").is_err()
        {
            assert_eq!(
                resolve_auth0_client_id(None).unwrap(),
                super::super::auth0_defaults::AUTH0_NATIVE_CLIENT_ID
            );
        }
        if std::env::var("AUTH0_AUDIENCE").is_err() {
            assert_eq!(
                resolve_auth0_audience(None),
                super::super::auth0_defaults::AUTH0_AUDIENCE
            );
        }
    }

    #[test]
    fn seal_open_draft_roundtrip() {
        let state = DaemonState::new_in_memory_for_test().unwrap();
        state.merge_question(HumanDecision {
            id: "q1".into(),
            kind: "question".into(),
            prompt: "hello?".into(),
            options: None,
        });
        let plain = serde_json::to_vec(&state.get_draft_plain()).unwrap();
        let env = state.seal_to_self(&plain).unwrap();
        let opened = state.open_envelope(&env).unwrap();
        assert_eq!(opened, plain);
    }

    #[test]
    fn get_thread_opens_sealed_bundle() {
        let state = DaemonState::new_in_memory_for_test().unwrap();
        let bundle = MutandeBundle {
            subject: Some("handoff".into()),
            context: Some("please review".into()),
            ..Default::default()
        };
        let plain = serde_json::to_vec(&bundle).unwrap();
        let env = state.seal_to_self(&plain).unwrap();

        let detail = ThreadDetail {
            thread: ThreadMeta {
                id: "t1".into(),
                kind: ThreadKind::Direct,
                status: ThreadStatus::Open,
                from: "alice@acme".into(),
                from_user_id: "u1".into(),
                from_agent_id: None,
                audience: "bob@acme".into(),
                audience_agent_id: None,
                audience_wire_path: None,
                org_id: "o1".into(),
                participant_count: 2,
                reply_count: 0,
                your_status: None,
                created_at: "2026-01-01T00:00:00Z".into(),
                updated_at: "2026-01-01T00:00:00Z".into(),
                last_from: None,
                last_subject: None,
                last_preview: None,
            },
            messages: vec![ThreadMessage {
                id: "m1".into(),
                thread_id: "t1".into(),
                from_user_id: "u1".into(),
                from_handle: "alice@acme".into(),
                envelope: env,
                created_at: "2026-01-01T00:00:00Z".into(),
                sender_only: None,
                parent_message_id: None,
                upvotes: None,
            }],
        };

        let opened = state.open_thread_detail(detail);
        assert_eq!(opened.messages.len(), 1);
        let msg = &opened.messages[0];
        assert!(msg.open_error.is_none());
        assert!(msg.envelope.is_none());
        assert_eq!(msg.bundle.as_ref(), Some(&bundle));
    }

    #[test]
    fn get_thread_surfaces_open_error_for_foreign_envelope() {
        use crate::crypto::{DevicePubKey, seal};
        use crypto_box::aead::OsRng;
        use crypto_box::SecretKey;

        let state = DaemonState::new_in_memory_for_test().unwrap();
        let other_sk = SecretKey::generate(&mut OsRng);
        let other_pk = DevicePubKey(other_sk.public_key().to_bytes());
        let env = seal(b"{\"subject\":\"secret\"}", &[other_pk]).unwrap();

        let detail = ThreadDetail {
            thread: ThreadMeta {
                id: "t-fail".into(),
                kind: ThreadKind::Direct,
                status: ThreadStatus::Open,
                from: "alice@acme".into(),
                from_user_id: "u1".into(),
                from_agent_id: None,
                audience: "bob@acme".into(),
                audience_agent_id: None,
                audience_wire_path: None,
                org_id: "o1".into(),
                participant_count: 2,
                reply_count: 0,
                your_status: None,
                created_at: "2026-01-01T00:00:00Z".into(),
                updated_at: "2026-01-01T00:00:00Z".into(),
                last_from: None,
                last_subject: None,
                last_preview: None,
            },
            messages: vec![ThreadMessage {
                id: "m-fail".into(),
                thread_id: "t-fail".into(),
                from_user_id: "u1".into(),
                from_handle: "alice@acme".into(),
                envelope: env,
                created_at: "2026-01-01T00:00:00Z".into(),
                sender_only: None,
                parent_message_id: None,
                upvotes: None,
            }],
        };

        let opened = state.open_thread_detail(detail);
        let msg = &opened.messages[0];
        assert!(msg.bundle.is_none());
        assert!(
            msg.envelope.is_none(),
            "open failure must not return ciphertext/wraps to agents"
        );
        assert!(
            msg.open_error.as_deref().is_some_and(|e| !e.is_empty()),
            "expected open_error, got {:?}",
            msg.open_error
        );
    }

    #[test]
    fn own_safety_number_is_stable() {
        let state = DaemonState::new_in_memory_for_test().unwrap();
        let a = state.own_safety_number().unwrap();
        let b = state.own_safety_number().unwrap();
        assert_eq!(a.fingerprint, b.fingerprint);
        assert!(a.uri.starts_with("mutande:safety:"));
        assert_eq!(a.fingerprint.split_whitespace().count(), 12);
    }

    #[test]
    fn inline_non_bundle_plaintext_surfaces_decode_error() {
        let state = DaemonState::new_in_memory_for_test().unwrap();
        let env = state.seal_to_self(b"not-json-bundle").unwrap();
        assert!(env.blob_id.is_none());
        let detail = ThreadDetail {
            thread: ThreadMeta {
                id: "t-bad".into(),
                kind: ThreadKind::Direct,
                status: ThreadStatus::Open,
                from: "alice@acme".into(),
                from_user_id: "u1".into(),
                from_agent_id: None,
                audience: "bob@acme".into(),
                audience_agent_id: None,
                audience_wire_path: None,
                org_id: "o1".into(),
                participant_count: 2,
                reply_count: 0,
                your_status: None,
                created_at: "2026-01-01T00:00:00Z".into(),
                updated_at: "2026-01-01T00:00:00Z".into(),
                last_from: None,
                last_subject: None,
                last_preview: None,
            },
            messages: vec![ThreadMessage {
                id: "m-bad".into(),
                thread_id: "t-bad".into(),
                from_user_id: "u1".into(),
                from_handle: "alice@acme".into(),
                envelope: env,
                created_at: "2026-01-01T00:00:00Z".into(),
                sender_only: None,
                parent_message_id: None,
                upvotes: None,
            }],
        };
        let opened = state.open_thread_detail(detail);
        let msg = &opened.messages[0];
        assert!(msg.bundle.is_none());
        assert!(
            msg.open_error
                .as_deref()
                .is_some_and(|e| e.contains("decode bundle")),
            "inline garbage must not be treated as blob artifact: {:?}",
            msg.open_error
        );
    }

    #[tokio::test]
    async fn blob_seal_upload_download_open_e2e() {
        use crate::hub_client::{pubkey_to_hub_string, HubConfig};
        use std::sync::Mutex as StdMutex;
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, MockServer, Request, ResponseTemplate};

        let state = DaemonState::new_in_memory_for_test().unwrap();
        let own_pk = state.device_public().unwrap();
        let pk_hub = pubkey_to_hub_string(&own_pk);

        let server = MockServer::start().await;
        let blob_store: Arc<StdMutex<Option<Vec<u8>>>> = Arc::new(StdMutex::new(None));
        let blob_store_put = Arc::clone(&blob_store);
        let blob_store_get = Arc::clone(&blob_store);

        Mock::given(method("GET"))
            .and(path("/v1/contacts"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "contacts": [
                    { "handle": "bob@acme", "pubkey": pk_hub }
                ]
            })))
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/v1/blobs/upload-url"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "blob_id": "blob-e2e-1",
                "upload_url": format!("{}/mock-r2/blob-e2e-1?upload=1", server.uri()),
                "expires_at": "2099-01-01T00:00:00Z"
            })))
            .mount(&server)
            .await;

        Mock::given(method("PUT"))
            .and(path("/mock-r2/blob-e2e-1"))
            .respond_with(move |req: &Request| {
                *blob_store_put.lock().unwrap() = Some(req.body.clone());
                ResponseTemplate::new(200)
            })
            .mount(&server)
            .await;

        let captured_env: Arc<StdMutex<Option<serde_json::Value>>> =
            Arc::new(StdMutex::new(None));
        let captured_env_write = Arc::clone(&captured_env);
        Mock::given(method("POST"))
            .and(path("/v1/threads"))
            .respond_with(move |req: &Request| {
                let body: serde_json::Value = serde_json::from_slice(&req.body).unwrap();
                *captured_env_write.lock().unwrap() = Some(body["envelope"].clone());
                ResponseTemplate::new(201).set_body_json(&serde_json::json!({
                    "thread": {
                        "id": "thread-blob-1",
                        "kind": "direct",
                        "status": "open",
                        "from": "alice@acme",
                        "from_user_id": "u-alice",
                        "audience": "bob@acme",
                        "org_id": "org-1",
                        "participant_count": 2,
                        "reply_count": 0,
                        "created_at": "2026-01-01T00:00:00Z",
                        "updated_at": "2026-01-01T00:00:00Z"
                    },
                    "message_id": "msg-blob-1"
                }))
            })
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/v1/blobs/blob-e2e-1/download-url"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "download_url": format!("{}/mock-r2/blob-e2e-1", server.uri()),
                "expires_at": "2099-01-01T00:00:00Z",
                "meta": {
                    "id": "blob-e2e-1",
                    "org_id": "org-1",
                    "owner_user_id": "u-alice",
                    "size_bytes": 1,
                    "created_at": "2026-01-01T00:00:00Z"
                }
            })))
            .mount(&server)
            .await;

        Mock::given(method("GET"))
            .and(path("/mock-r2/blob-e2e-1"))
            .respond_with(move |_req: &Request| {
                let bytes = blob_store_get.lock().unwrap().clone().unwrap_or_default();
                ResponseTemplate::new(200).set_body_bytes(bytes)
            })
            .mount(&server)
            .await;

        let hub = HubClient::new(HubConfig::new(server.uri(), "test-jwt")).unwrap();
        state.attach_hub_for_test(hub);

        let artifact = b"large codebase tarball bytes for e2e";
        let forwarded = state
            .forward_blob(
                "bob@acme",
                artifact,
                Some("code drop"),
                Some("codebase.txt"),
                None,
            )
            .await
            .unwrap();
        assert_eq!(forwarded.thread_ids, vec!["thread-blob-1".to_string()]);
        assert_eq!(forwarded.recipients, vec!["bob@acme".to_string()]);

        let env_json = captured_env.lock().unwrap().clone().unwrap();
        assert_eq!(env_json["blob_id"], "blob-e2e-1");
        assert!(env_json["ciphertext"].as_array().unwrap().is_empty());
        assert!(env_json["sha256"].as_str().unwrap().len() == 64);
        assert!(blob_store.lock().unwrap().as_ref().unwrap().len() > 0);

        let env: Envelope = serde_json::from_value(env_json).unwrap();
        let opened = state.open_envelope_maybe_blob(&env).await.unwrap();
        let bundle: MutandeBundle = serde_json::from_slice(&opened).unwrap();
        assert_eq!(bundle.subject.as_deref(), Some("code drop"));
        assert_eq!(bundle.resources.len(), 1);
        assert_eq!(bundle.resources[0].name, "codebase.txt");
        assert_eq!(bundle.resources[0].mime, "text/plain");
        assert_eq!(
            bundle.resources[0].content.as_deref(),
            Some("large codebase tarball bytes for e2e")
        );
    }

    #[test]
    fn legacy_raw_text_blob_inlines_for_agents() {
        let state = DaemonState::new_in_memory_for_test().unwrap();
        let body = "# Notice of Fine\n\nPay one upvote.";
        let mut env = state.seal_to_self(body.as_bytes()).unwrap();
        // Mark as blob while keeping inline ciphertext so sync open works.
        env.blob_id = Some("legacy-raw-1".into());
        let detail = ThreadDetail {
            thread: ThreadMeta {
                id: "t-blob".into(),
                kind: ThreadKind::Direct,
                status: ThreadStatus::Open,
                from: "alice@acme/cursor".into(),
                from_user_id: "u1".into(),
                from_agent_id: None,
                audience: "alice@acme/claude".into(),
                audience_agent_id: None,
                audience_wire_path: None,
                org_id: "o1".into(),
                participant_count: 2,
                reply_count: 0,
                your_status: None,
                created_at: "2026-01-01T00:00:00Z".into(),
                updated_at: "2026-01-01T00:00:00Z".into(),
                last_from: None,
                last_subject: None,
                last_preview: None,
            },
            messages: vec![ThreadMessage {
                id: "m-blob".into(),
                thread_id: "t-blob".into(),
                from_user_id: "u1".into(),
                from_handle: "alice@acme/cursor".into(),
                envelope: env,
                created_at: "2026-01-01T00:00:00Z".into(),
                sender_only: None,
                parent_message_id: None,
                upvotes: None,
            }],
        };
        let opened = state.open_thread_detail(detail);
        let msg = &opened.messages[0];
        let bundle = msg.bundle.as_ref().expect("bundle");
        assert_eq!(bundle.notes.as_deref(), Some(body));
        assert_eq!(bundle.resources[0].name, "artifact.md");
        assert_eq!(bundle.resources[0].mime, "text/markdown");
        assert_eq!(bundle.resources[0].content.as_deref(), Some(body));
        assert!(msg.open_error.is_none());
    }

    async fn mock_solo_hub(server: &wiremock::MockServer) {
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, ResponseTemplate};

        Mock::given(method("GET"))
            .and(path("/v1/contacts"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "contacts": [
                    { "handle": "@all@tbhco", "pubkey": null, "devices": [] }
                ]
            })))
            .mount(server)
            .await;

        Mock::given(method("GET"))
            .and(path("/v1/me"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "auth0_sub": "auth0|solo",
                "needs_onboarding": false,
                "onboarded": true,
                "user": {
                    "id": "u-solo",
                    "handle": "solo@tbhco",
                    "org_id": "org-solo",
                    "created_at": "2026-01-01T00:00:00Z"
                },
                "org": {
                    "id": "org-solo",
                    "slug": "tbhco",
                    "name": "TBH",
                    "created_at": "2026-01-01T00:00:00Z"
                }
            })))
            .mount(server)
            .await;

        Mock::given(method("GET"))
            .and(path("/v1/agents"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "agents": [
                    { "id": "a-cursor", "user_id": "u-solo", "slug": "cursor", "created_at": "2026-01-01T00:00:00Z" },
                    { "id": "a-claude", "user_id": "u-solo", "slug": "claude", "created_at": "2026-01-01T00:00:00Z" }
                ],
                "default_agent_id": "a-cursor"
            })))
            .mount(server)
            .await;
    }

    #[tokio::test]
    async fn sole_member_all_resolves_to_own_pubkey_and_seals() {
        use crate::crypto::seal;
        use crate::hub_client::HubConfig;
        use wiremock::MockServer;

        let state = DaemonState::new_in_memory_for_test().unwrap();
        let own_pk = state.device_public().unwrap();
        let server = MockServer::start().await;
        mock_solo_hub(&server).await;
        state.attach_hub_for_test(HubClient::new(HubConfig::new(server.uri(), "tok")).unwrap());
        state.set_connected_agent_slug_for_test(Some("cursor"));

        let keys = state
            .resolve_recipient_pubkeys("@all@tbhco")
            .await
            .unwrap();
        assert_eq!(keys.len(), 1);
        assert_eq!(keys[0].0, own_pk.0);

        let env = seal(b"{\"subject\":\"solo all\"}", &keys).unwrap();
        let opened = state.open_envelope(&env).unwrap();
        assert_eq!(opened, b"{\"subject\":\"solo all\"}");
    }

    #[tokio::test]
    async fn self_agent_handoff_seals_to_own_device() {
        use crate::crypto::seal;
        use crate::hub_client::HubConfig;
        use wiremock::MockServer;

        let state = DaemonState::new_in_memory_for_test().unwrap();
        let own_pk = state.device_public().unwrap();
        let server = MockServer::start().await;
        mock_solo_hub(&server).await;
        state.attach_hub_for_test(HubClient::new(HubConfig::new(server.uri(), "tok")).unwrap());
        state.set_connected_agent_slug_for_test(Some("cursor"));

        state
            .assert_recipient_allowed("solo@tbhco/claude", None)
            .await
            .unwrap();
        let keys = state
            .resolve_recipient_pubkeys("solo@tbhco/claude")
            .await
            .unwrap();
        assert_eq!(keys[0].0, own_pk.0);
        let env = seal(b"{\"subject\":\"cursor to claude\"}", &keys).unwrap();
        assert_eq!(
            state.open_envelope(&env).unwrap(),
            b"{\"subject\":\"cursor to claude\"}"
        );
    }

    #[tokio::test]
    async fn same_agent_self_loop_rejected() {
        use crate::hub_client::HubConfig;
        use wiremock::MockServer;

        let state = DaemonState::new_in_memory_for_test().unwrap();
        let server = MockServer::start().await;
        mock_solo_hub(&server).await;
        state.attach_hub_for_test(HubClient::new(HubConfig::new(server.uri(), "tok")).unwrap());
        state.set_connected_agent_slug_for_test(Some("cursor"));

        let err = state
            .assert_recipient_allowed("solo@tbhco/cursor", None)
            .await
            .unwrap_err();
        assert!(
            err.to_string().contains("same agent"),
            "got: {err}"
        );

        let bare_err = state
            .assert_recipient_allowed("solo@tbhco", None)
            .await
            .unwrap_err();
        assert!(
            bare_err.to_string().contains("same agent"),
            "got: {bare_err}"
        );
    }

    #[test]
    fn self_handoff_visible_to_target_agent() {
        let thread = ThreadMeta {
            id: "t1".into(),
            kind: ThreadKind::Direct,
            status: ThreadStatus::Open,
            from: "solo@tbhco/cursor".into(),
            from_user_id: "u-solo".into(),
            from_agent_id: Some("a-cursor".into()),
            audience: "solo@tbhco/claude".into(),
            audience_agent_id: Some("a-claude".into()),
            audience_wire_path: Some("tbhco/solo/claude".into()),
            org_id: "org-solo".into(),
            participant_count: 1,
            reply_count: 0,
            your_status: None,
            created_at: "2026-01-01T00:00:00Z".into(),
            updated_at: "2026-01-01T00:00:00Z".into(),
            last_from: None,
            last_subject: None,
            last_preview: None,
        };
        assert!(thread_visible_for_agent(&thread, "u-solo", "cursor", "cursor"));
        assert!(thread_visible_for_agent(&thread, "u-solo", "claude", "cursor"));
        assert!(!thread_visible_for_agent(&thread, "u-solo", "chatgpt", "cursor"));
    }

    #[test]
    fn outbound_to_other_user_does_not_leak_by_audience_slug() {
        // alice/cursor → bob@acme/claude must not appear in alice's own `claude` agent.
        let thread = ThreadMeta {
            id: "t-ext".into(),
            kind: ThreadKind::Direct,
            status: ThreadStatus::Open,
            from: "alice@acme/cursor".into(),
            from_user_id: "u-alice".into(),
            from_agent_id: Some("a-cursor".into()),
            audience: "bob@acme/claude".into(),
            audience_agent_id: Some("a-bob-claude".into()),
            audience_wire_path: Some("acme/bob/claude".into()),
            org_id: "org-acme".into(),
            participant_count: 2,
            reply_count: 0,
            your_status: None,
            created_at: "2026-01-01T00:00:00Z".into(),
            updated_at: "2026-01-01T00:00:00Z".into(),
            last_from: None,
            last_subject: None,
            last_preview: None,
        };
        assert!(thread_visible_for_agent(&thread, "u-alice", "cursor", "cursor"));
        assert!(!thread_visible_for_agent(
            &thread, "u-alice", "claude", "cursor"
        ));
        // Recipient bob's claude still sees it.
        assert!(thread_visible_for_agent(&thread, "u-bob", "claude", "cursor"));
    }

    #[test]
    fn agent_your_status_self_handoff_audience_pending_sender_waiting() {
        // Hub may report replied (Waiting) for the human; chatgpt still needs action.
        let thread = ThreadMeta {
            id: "t-self".into(),
            kind: ThreadKind::Direct,
            status: ThreadStatus::Open,
            from: "solo@tbhco/cursor".into(),
            from_user_id: "u-solo".into(),
            from_agent_id: Some("a-cursor".into()),
            audience: "solo@tbhco/chatgpt".into(),
            audience_agent_id: Some("a-chatgpt".into()),
            audience_wire_path: Some("tbhco/solo/chatgpt".into()),
            org_id: "org-solo".into(),
            participant_count: 2,
            reply_count: 0,
            your_status: Some(YourStatus::Replied),
            created_at: "2026-01-01T00:00:00Z".into(),
            updated_at: "2026-01-01T00:00:00Z".into(),
            last_from: None,
            last_subject: None,
            last_preview: None,
        };
        assert_eq!(
            agent_your_status(&thread, "u-solo", "chatgpt", "cursor"),
            YourStatus::Pending
        );
        assert_eq!(
            agent_your_status(&thread, "u-solo", "cursor", "cursor"),
            YourStatus::Replied
        );
    }

    #[test]
    fn my_agents_broadcast_visible_to_all_own_agents() {
        let thread = ThreadMeta {
            id: "t-all".into(),
            kind: ThreadKind::Broadcast,
            status: ThreadStatus::Open,
            from: "solo@tbhco/cursor".into(),
            from_user_id: "u-solo".into(),
            from_agent_id: Some("a-cursor".into()),
            audience: "@all".into(),
            audience_agent_id: None,
            audience_wire_path: None,
            org_id: "org-solo".into(),
            participant_count: 2,
            reply_count: 0,
            your_status: None,
            created_at: "2026-01-01T00:00:00Z".into(),
            updated_at: "2026-01-01T00:00:00Z".into(),
            last_from: None,
            last_subject: None,
            last_preview: None,
        };
        assert!(thread_visible_for_agent(&thread, "u-solo", "cursor", "cursor"));
        assert!(thread_visible_for_agent(&thread, "u-solo", "claude", "cursor"));
        assert!(thread_visible_for_agent(&thread, "u-solo", "chatgpt", "cursor"));
        assert!(!thread_visible_for_agent(&thread, "u-other", "cursor", "cursor"));
        // Unreplied group: non-senders have the ball; sender is Waiting.
        assert_eq!(
            agent_your_status(&thread, "u-solo", "claude", "cursor"),
            YourStatus::Pending
        );
        assert_eq!(
            agent_your_status(&thread, "u-solo", "chatgpt", "cursor"),
            YourStatus::Pending
        );
        assert_eq!(
            agent_your_status(&thread, "u-solo", "cursor", "cursor"),
            YourStatus::Replied
        );
    }

    #[test]
    fn org_broadcast_still_default_agent_only() {
        let thread = ThreadMeta {
            id: "t-org".into(),
            kind: ThreadKind::Broadcast,
            status: ThreadStatus::Open,
            from: "alice@acme/cursor".into(),
            from_user_id: "u-alice".into(),
            from_agent_id: Some("a-cursor".into()),
            audience: "@all@acme".into(),
            audience_agent_id: None,
            audience_wire_path: None,
            org_id: "org-acme".into(),
            participant_count: 3,
            reply_count: 0,
            your_status: None,
            created_at: "2026-01-01T00:00:00Z".into(),
            updated_at: "2026-01-01T00:00:00Z".into(),
            last_from: None,
            last_subject: None,
            last_preview: None,
        };
        assert!(thread_visible_for_agent(&thread, "u-bob", "cursor", "cursor"));
        assert!(!thread_visible_for_agent(&thread, "u-bob", "claude", "cursor"));
    }

    #[tokio::test]
    async fn shorthand_self_agent_allowed_and_loop_rejected() {
        use crate::hub_client::HubConfig;
        use wiremock::MockServer;

        let state = DaemonState::new_in_memory_for_test().unwrap();
        let server = MockServer::start().await;
        mock_solo_hub(&server).await;
        state.attach_hub_for_test(HubClient::new(HubConfig::new(server.uri(), "tok")).unwrap());
        state.set_connected_agent_slug_for_test(Some("cursor"));

        state.assert_recipient_allowed("@claude", None).await.unwrap();
        state.assert_recipient_allowed("@all", None).await.unwrap();

        let err = state.assert_recipient_allowed("@cursor", None).await.unwrap_err();
        assert!(err.to_string().contains("same agent"), "got: {err}");
    }

    #[tokio::test]
    async fn resolve_pubkeys_for_shorthand_and_my_agents() {
        let state = DaemonState::new_in_memory_for_test().unwrap();
        let own = state.device_public().unwrap();
        let for_slug = state.resolve_recipient_pubkeys("@claude").await.unwrap();
        assert_eq!(for_slug.len(), 1);
        assert_eq!(for_slug[0].0, own.0);
        let for_all = state.resolve_recipient_pubkeys("@all").await.unwrap();
        assert_eq!(for_all.len(), 1);
        assert_eq!(for_all[0].0, own.0);
    }

    #[tokio::test]
    async fn expand_hub_recipients_shorthand_for_legacy_prod() {
        use crate::hub_client::HubConfig;
        use wiremock::MockServer;

        let state = DaemonState::new_in_memory_for_test().unwrap();
        let server = MockServer::start().await;
        mock_solo_hub(&server).await;
        state.attach_hub_for_test(HubClient::new(HubConfig::new(server.uri(), "tok")).unwrap());
        state.set_connected_agent_slug_for_test(Some("cursor"));

        let claude = state.expand_hub_recipients("@claude", None).await.unwrap();
        assert_eq!(claude, vec!["solo@tbhco/claude".to_string()]);

        let all = state.expand_hub_recipients("@all", None).await.unwrap();
        assert_eq!(all, vec!["@all".to_string()]);

        let passthrough = state
            .expand_hub_recipients("solo@tbhco/claude", None)
            .await
            .unwrap();
        assert_eq!(passthrough, vec!["solo@tbhco/claude".to_string()]);
    }

    /// Bare `@all` with multiple agents → one shared group recipient, not N directs.
    #[tokio::test]
    async fn expand_all_is_single_group_recipient() {
        use crate::hub_client::HubConfig;
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let state = DaemonState::new_in_memory_for_test().unwrap();
        let server = MockServer::start().await;

        Mock::given(method("GET"))
            .and(path("/v1/me"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "auth0_sub": "auth0|solo",
                "needs_onboarding": false,
                "onboarded": true,
                "user": {
                    "id": "u-solo",
                    "handle": "tawanda@tbhco",
                    "org_id": "org-solo",
                    "created_at": "2026-01-01T00:00:00Z"
                },
                "org": {
                    "id": "org-solo",
                    "slug": "tbhco",
                    "name": "TBH",
                    "created_at": "2026-01-01T00:00:00Z"
                }
            })))
            .mount(&server)
            .await;

        Mock::given(method("GET"))
            .and(path("/v1/agents"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "agents": [
                    { "id": "a-claude", "user_id": "u-solo", "slug": "claude", "created_at": "2026-01-01T00:00:00Z" },
                    { "id": "a-cursor", "user_id": "u-solo", "slug": "cursor", "created_at": "2026-01-01T00:00:00Z" },
                    { "id": "a-chatgpt", "user_id": "u-solo", "slug": "chatgpt", "created_at": "2026-01-01T00:00:00Z" }
                ],
                "default_agent_id": "a-cursor"
            })))
            .mount(&server)
            .await;

        state.attach_hub_for_test(HubClient::new(HubConfig::new(server.uri(), "tok")).unwrap());
        state.set_connected_agent_slug_for_test(Some("claude"));

        let all = state.expand_hub_recipients("@all", None).await.unwrap();
        assert_eq!(all, vec!["@all".to_string()]);
    }

    /// Stale shared connected_agent_slug=cursor must not win when the MCP call
    /// stamps agent_slug=claude (multi-host register_agent race).
    #[tokio::test]
    async fn reply_uses_per_request_agent_slug_not_shared_slot() {
        use crate::hub_client::{pubkey_to_hub_string, HubConfig};
        use wiremock::matchers::{body_partial_json, method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let state = DaemonState::new_in_memory_for_test().unwrap();
        let own_pk = state.device_public().unwrap();
        let pk_hub = pubkey_to_hub_string(&own_pk);
        let server = MockServer::start().await;

        Mock::given(method("GET"))
            .and(path("/v1/me"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "auth0_sub": "auth0|solo",
                "needs_onboarding": false,
                "onboarded": true,
                "user": {
                    "id": "u-solo",
                    "handle": "tawanda@tbhco",
                    "org_id": "org-solo",
                    "created_at": "2026-01-01T00:00:00Z"
                },
                "org": {
                    "id": "org-solo",
                    "slug": "tbhco",
                    "name": "TBH",
                    "created_at": "2026-01-01T00:00:00Z"
                }
            })))
            .mount(&server)
            .await;

        Mock::given(method("GET"))
            .and(path("/v1/threads/t-reply"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "thread": {
                    "id": "t-reply",
                    "kind": "direct",
                    "status": "open",
                    "from": "bob@tbhco/cursor",
                    "from_user_id": "u-bob",
                    "from_agent_id": "a-bob-cursor",
                    "audience": "tawanda@tbhco/claude",
                    "audience_agent_id": "a-claude",
                    "audience_wire_path": "tbhco/tawanda/claude",
                    "org_id": "org-solo",
                    "participant_count": 2,
                    "reply_count": 0,
                    "created_at": "2026-01-01T00:00:00Z",
                    "updated_at": "2026-01-01T00:00:00Z"
                },
                "messages": []
            })))
            .mount(&server)
            .await;

        Mock::given(method("GET"))
            .and(path("/v1/contacts"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "contacts": [{
                    "handle": "bob@tbhco",
                    "pubkey": pk_hub,
                    "devices": [{ "pubkey": pk_hub, "platform": "macos" }]
                }]
            })))
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/v1/threads/t-reply/replies"))
            .and(body_partial_json(serde_json::json!({ "from_agent": "claude" })))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "message_id": "m-reply"
            })))
            .expect(1)
            .mount(&server)
            .await;

        state.attach_hub_for_test(HubClient::new(HubConfig::new(server.uri(), "tok")).unwrap());
        // Shared slot looks like cursor (last host that registered) — must not win.
        state.set_connected_agent_slug_for_test(Some("cursor"));

        state
            .reply_to_thread(
                "t-reply",
                MutandeBundle {
                    subject: Some("from claude".into()),
                    ..Default::default()
                },
                None,
                Some("claude"),
            )
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn reply_rejects_empty_bundle() {
        let state = DaemonState::new_in_memory_for_test().unwrap();
        let err = state
            .reply_to_thread("t-empty", MutandeBundle::default(), None, Some("claude"))
            .await
            .unwrap_err();
        assert!(
            err.to_string().contains("reply bundle is empty"),
            "got: {err}"
        );
    }

    #[tokio::test]
    async fn ping_thread_fans_out_via_all() {
        use crate::hub_client::HubConfig;
        use std::sync::atomic::{AtomicUsize, Ordering};
        use std::sync::Arc;
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let state = DaemonState::new_in_memory_for_test().unwrap();
        let server = MockServer::start().await;
        mock_solo_hub(&server).await;

        let create_count = Arc::new(AtomicUsize::new(0));
        let create_count2 = create_count.clone();
        Mock::given(method("POST"))
            .and(path("/v1/threads"))
            .respond_with(move |_req: &wiremock::Request| {
                let n = create_count2.fetch_add(1, Ordering::SeqCst) + 1;
                ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                    "thread": {
                        "id": format!("t-ping-{n}"),
                        "kind": "direct",
                        "status": "open",
                        "from": "solo@tbhco/cursor",
                        "from_user_id": "u-solo",
                        "audience": "solo@tbhco/claude",
                        "org_id": "org-solo",
                        "participant_count": 2,
                        "reply_count": 0,
                        "created_at": "2026-01-01T00:00:00Z",
                        "updated_at": "2026-01-01T00:00:00Z"
                    },
                    "message_id": format!("m-ping-{n}")
                }))
            })
            .mount(&server)
            .await;

        state.attach_hub_for_test(HubClient::new(HubConfig::new(server.uri(), "tok")).unwrap());
        state.set_connected_agent_slug_for_test(Some("cursor"));

        let result = state
            .ping("@all", PingKind::Thread, None)
            .await
            .unwrap();
        assert_eq!(result.recipients, vec!["solo@tbhco/claude".to_string()]);
        assert_eq!(result.thread_ids.len(), 1);
        assert_eq!(create_count.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn ping_thread_solo_all_falls_back_to_bare_handle() {
        use crate::hub_client::HubConfig;
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let state = DaemonState::new_in_memory_for_test().unwrap();
        let server = MockServer::start().await;

        Mock::given(method("GET"))
            .and(path("/v1/me"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "auth0_sub": "auth0|solo",
                "needs_onboarding": false,
                "onboarded": true,
                "user": {
                    "id": "u-solo",
                    "handle": "solo@tbhco",
                    "org_id": "org-solo",
                    "created_at": "2026-01-01T00:00:00Z"
                },
                "org": {
                    "id": "org-solo",
                    "slug": "tbhco",
                    "name": "TBH",
                    "created_at": "2026-01-01T00:00:00Z"
                }
            })))
            .mount(&server)
            .await;

        // Only the sending agent registered — expand @all would fail without fallback.
        Mock::given(method("GET"))
            .and(path("/v1/agents"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "agents": [
                    { "id": "a-cursor", "user_id": "u-solo", "slug": "cursor", "created_at": "2026-01-01T00:00:00Z" }
                ],
                "default_agent_id": "a-cursor"
            })))
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/v1/threads"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "thread": {
                    "id": "t-solo-ping",
                    "kind": "direct",
                    "status": "open",
                    "from": "solo@tbhco/cursor",
                    "from_user_id": "u-solo",
                    "audience": "solo@tbhco",
                    "org_id": "org-solo",
                    "participant_count": 1,
                    "reply_count": 0,
                    "created_at": "2026-01-01T00:00:00Z",
                    "updated_at": "2026-01-01T00:00:00Z"
                },
                "message_id": "m-solo-ping"
            })))
            .expect(1)
            .mount(&server)
            .await;

        state.attach_hub_for_test(HubClient::new(HubConfig::new(server.uri(), "tok")).unwrap());
        state.set_connected_agent_slug_for_test(Some("cursor"));

        let result = state
            .ping("@all", PingKind::Thread, None)
            .await
            .unwrap();
        assert_eq!(result.recipients, vec!["solo@tbhco".to_string()]);
        assert_eq!(result.thread_ids, vec!["t-solo-ping".to_string()]);
    }

    #[tokio::test]
    async fn health_ping_auto_pongs_on_get_thread() {
        use crate::hub_client::HubConfig;
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let state = DaemonState::new_in_memory_for_test().unwrap();
        let server = MockServer::start().await;
        mock_solo_hub(&server).await;

        let ping_bundle = MutandeBundle {
            subject: Some("Ping".into()),
            notes: Some("health ping".into()),
            ping_kind: Some(PingKind::Health),
            ..Default::default()
        };
        let plain = serde_json::to_vec(&ping_bundle).unwrap();
        let env = state.seal_to_self(&plain).unwrap();

        let detail = ThreadDetail {
            thread: ThreadMeta {
                id: "t-health".into(),
                kind: ThreadKind::Direct,
                status: ThreadStatus::Open,
                from: "solo@tbhco/claude".into(),
                from_user_id: "u-solo".into(),
                from_agent_id: None,
                audience: "solo@tbhco/cursor".into(),
                audience_agent_id: None,
                audience_wire_path: None,
                org_id: "org-solo".into(),
                participant_count: 2,
                reply_count: 0,
                your_status: Some(YourStatus::Pending),
                created_at: "2026-01-01T00:00:00Z".into(),
                updated_at: "2026-01-01T00:00:00Z".into(),
                last_from: None,
                last_subject: None,
                last_preview: None,
            },
            messages: vec![ThreadMessage {
                id: "m-health".into(),
                thread_id: "t-health".into(),
                from_user_id: "u-solo".into(),
                from_handle: "solo@tbhco/claude".into(),
                envelope: env,
                created_at: "2026-01-01T00:00:00Z".into(),
                sender_only: None,
                parent_message_id: None,
                upvotes: None,
            }],
        };

        Mock::given(method("GET"))
            .and(path("/v1/threads/t-health"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&detail))
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/v1/threads/t-health/replies"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "message_id": "m-pong"
            })))
            .expect(1)
            .mount(&server)
            .await;

        state.attach_hub_for_test(HubClient::new(HubConfig::new(server.uri(), "tok")).unwrap());
        state.set_connected_agent_slug_for_test(Some("cursor"));

        let opened = state.get_thread("t-health", None).await.unwrap();
        assert_eq!(opened.messages.len(), 1);
        assert!(state.is_processed("t-health"));
    }

    #[test]
    fn thread_needs_human_confirm_and_bare_question_only() {
        let base = ThreadMeta {
            id: "t1".into(),
            kind: ThreadKind::Direct,
            status: ThreadStatus::Open,
            from: "alice@acme/cursor".into(),
            from_user_id: "u1".into(),
            from_agent_id: None,
            audience: "alice@acme/claude".into(),
            audience_agent_id: None,
            audience_wire_path: None,
            org_id: "o1".into(),
            participant_count: 2,
            reply_count: 0,
            your_status: None,
            created_at: "t".into(),
            updated_at: "t".into(),
            last_from: None,
            last_subject: None,
            last_preview: None,
        };

        // Agent-targeted question → not Needs you.
        let agent_q = OpenedThreadDetail {
            thread: base.clone(),
            messages: vec![OpenedThreadMessage {
                id: "m1".into(),
                thread_id: "t1".into(),
                from_user_id: "u1".into(),
                from_handle: "alice@acme/cursor".into(),
                created_at: "t".into(),
                sender_only: None,
                parent_message_id: None,
                bundle: Some(MutandeBundle {
                    questions: vec![HumanDecision {
                        id: "q1".into(),
                        kind: "question".into(),
                        prompt: "agent work?".into(),
                        options: None,
                    }],
                    ..Default::default()
                }),
                envelope: None,
                open_error: None,
                upvotes: None,
            }],
        };
        assert!(!thread_needs_human(&agent_q));

        // confirm_forward → Needs you even on agent-addressed thread.
        let confirm = OpenedThreadDetail {
            thread: base.clone(),
            messages: vec![OpenedThreadMessage {
                id: "m2".into(),
                thread_id: "t1".into(),
                from_user_id: "u1".into(),
                from_handle: "alice@acme/cursor".into(),
                created_at: "t".into(),
                sender_only: None,
                parent_message_id: None,
                bundle: Some(MutandeBundle {
                    questions: vec![HumanDecision {
                        id: "c1".into(),
                        kind: "confirm_forward".into(),
                        prompt: "Send this?".into(),
                        options: None,
                    }],
                    ..Default::default()
                }),
                envelope: None,
                open_error: None,
                upvotes: None,
            }],
        };
        assert!(thread_needs_human(&confirm));

        // Bare-handle question → Needs you.
        let mut bare = base.clone();
        bare.audience = "bob@acme".into();
        let human_q = OpenedThreadDetail {
            thread: bare,
            messages: vec![OpenedThreadMessage {
                id: "m3".into(),
                thread_id: "t1".into(),
                from_user_id: "u1".into(),
                from_handle: "alice@acme/cursor".into(),
                created_at: "t".into(),
                sender_only: None,
                parent_message_id: None,
                bundle: Some(MutandeBundle {
                    questions: vec![HumanDecision {
                        id: "q2".into(),
                        kind: "question".into(),
                        prompt: "Approve roadmap?".into(),
                        options: None,
                    }],
                    ..Default::default()
                }),
                envelope: None,
                open_error: None,
                upvotes: None,
            }],
        };
        assert!(thread_needs_human(&human_q));

        // Answered confirm → not Needs you.
        let answered = OpenedThreadDetail {
            thread: base,
            messages: vec![
                OpenedThreadMessage {
                    id: "m4".into(),
                    thread_id: "t1".into(),
                    from_user_id: "u1".into(),
                    from_handle: "alice@acme/cursor".into(),
                    created_at: "t".into(),
                    sender_only: None,
                    parent_message_id: None,
                    bundle: Some(MutandeBundle {
                        questions: vec![HumanDecision {
                            id: "c2".into(),
                            kind: "confirm_forward".into(),
                            prompt: "Send?".into(),
                            options: None,
                        }],
                        ..Default::default()
                    }),
                    envelope: None,
                    open_error: None,
                    upvotes: None,
                },
                OpenedThreadMessage {
                    id: "m5".into(),
                    thread_id: "t1".into(),
                    from_user_id: "u1".into(),
                    from_handle: "alice@acme".into(),
                    created_at: "t2".into(),
                    sender_only: None,
                    parent_message_id: Some("m4".into()),
                    bundle: Some(MutandeBundle {
                        answers: vec![BundleAnswer {
                            question_id: "c2".into(),
                            answer: "yes".into(),
                        }],
                        ..Default::default()
                    }),
                    envelope: None,
                    open_error: None,
                    upvotes: None,
                },
            ],
        };
        assert!(!thread_needs_human(&answered));
    }

    #[test]
    fn bundle_body_preview_skips_subject() {
        assert_eq!(
            bundle_body_preview(&MutandeBundle {
                notes: Some("  hi there  ".into()),
                subject: Some("Ping".into()),
                ..Default::default()
            }),
            Some("hi there".into())
        );
        assert_eq!(
            bundle_body_preview(&MutandeBundle {
                subject: Some("Ping".into()),
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            bundle_body_preview(&MutandeBundle {
                questions: vec![HumanDecision {
                    id: "q1".into(),
                    kind: "question".into(),
                    prompt: "Ship it?".into(),
                    options: None,
                }],
                ..Default::default()
            }),
            Some("Ship it?".into())
        );
    }

    #[test]
    fn ping_kind_parse_and_serde() {
        assert_eq!(PingKind::parse("health").unwrap(), PingKind::Health);
        assert_eq!(PingKind::parse("thread").unwrap(), PingKind::Thread);
        assert!(PingKind::parse("nope").is_err());
        let b = MutandeBundle {
            ping_kind: Some(PingKind::Thread),
            subject: Some("Ping".into()),
            ..Default::default()
        };
        let v = serde_json::to_value(&b).unwrap();
        assert_eq!(v["ping_kind"], "thread");
        let back: MutandeBundle = serde_json::from_value(v).unwrap();
        assert_eq!(back.ping_kind, Some(PingKind::Thread));
    }
}
