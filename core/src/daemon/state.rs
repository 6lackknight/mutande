use std::collections::HashSet;
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result, bail};
use crypto_box::aead::OsRng;
use crypto_box::SecretKey;
use serde::{Deserialize, Serialize};

use crate::address::{agent_suffix, is_broadcast_handle, strip_agent_suffix};
use crate::crypto::{
    DevicePubKey, DeviceSecretKey, Envelope, IdentityStore, MemoryStore, StoreError,
    fingerprints_match, open, open_from_bytes, safety_number, safety_uri, seal, seal_to_temp,
    with_blob_id,
};

#[cfg(target_os = "macos")]
use crate::crypto::KeychainIdentityStore;
use crate::hub_client::{
    Agent, Contact, HubClient, MeResponse, ThreadDetail, ThreadFilter, ThreadKind, ThreadMessage,
    ThreadMeta, pubkey_from_hub_string,
};

use super::config::{DaemonConfig, config_path, load_config, save_config_at};
use super::oauth::{self, Auth0NativeConfig};

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
    pub bundle: Option<MutandeBundle>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub envelope: Option<Envelope>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub open_error: Option<String>,
}

/// Hub thread metadata plus locally opened (or failed) messages.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct OpenedThreadDetail {
    pub thread: ThreadMeta,
    pub messages: Vec<OpenedThreadMessage>,
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
            let _ = self.register_local_device(&hub).await;
        }
        let hub_url = self.config.lock().unwrap().hub_url.clone();
        Ok(status_from_me(&hub_url, &me))
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
        let _ = self.register_local_device(&hub).await;
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
        let _ = self.register_local_device(&hub).await;
        onboard_from_me(&me)
    }

    async fn register_local_device(&self, hub: &HubClient) -> Result<()> {
        let pubkey = self.device_public()?;
        let agent_slug = self.connected_agent_slug.lock().unwrap().clone();
        hub.register_device(&pubkey, "macos", agent_slug.as_deref()).await?;
        Ok(())
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

    async fn effective_agent_slug(&self) -> Option<String> {
        if let Some(s) = self.connected_agent_slug() {
            return Some(s);
        }
        self.default_agent_slug().await
    }

    async fn filter_threads_for_agent(&self, threads: Vec<ThreadMeta>) -> Result<Vec<ThreadMeta>> {
        let Some(hub) = self.hub_client() else {
            return Ok(threads);
        };
        let me = hub.me().await?;
        let user_id = me.user.as_ref().map(|u| u.id.as_str()).unwrap_or("");
        let default_slug = self.default_agent_slug().await;
        let Some(slug) = self.effective_agent_slug().await else {
            return Ok(threads);
        };
        let default_slug = default_slug.as_deref().unwrap_or(&slug);
        Ok(threads
            .into_iter()
            .filter(|t| thread_visible_for_agent(t, user_id, &slug, default_slug))
            .collect())
    }

    fn from_agent_for_send(&self) -> Option<String> {
        self.connected_agent_slug()
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

        if let Some(hub) = self.hub_client() {
            if let Ok(me) = hub.me().await {
                let mut status = status_from_me(&cfg.hub_url, &me);
                status.connected_agent = self.connected_agent_slug();
                status.default_agent = self.default_agent_slug().await;
                return Ok(status);
            }
        }

        // Tokens present but hub unreachable — keep last-known configured=false
        // for onboarding routing; Flutter treats transport errors separately.
        Ok(StatusResult {
            configured: false,
            signed_in: true,
            needs_onboarding: true,
            hub_url: cfg.hub_url,
            handle: None,
            org_id: None,
            email: None,
            connected_agent: self.connected_agent_slug(),
            default_agent: None,
        })
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

    pub async fn list_threads(&self, filter: Option<ThreadFilter>) -> Result<Vec<ThreadMeta>> {
        if let Some(hub) = self.hub_client() {
            let threads = hub.list_threads(filter).await?;
            return self.filter_threads_for_agent(threads).await;
        }
        Ok(vec![])
    }

    pub async fn get_thread(&self, thread_id: &str) -> Result<OpenedThreadDetail> {
        let Some(hub) = self.hub_client() else {
            bail!("hub not configured");
        };
        let detail = hub.get_thread(thread_id).await?;
        Ok(self.open_thread_detail_async(detail).await)
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
        let meta = |open_error: Option<String>| OpenedThreadMessage {
            id: msg.id.clone(),
            thread_id: msg.thread_id.clone(),
            from_user_id: msg.from_user_id.clone(),
            from_handle: msg.from_handle.clone(),
            created_at: msg.created_at.clone(),
            sender_only: msg.sender_only,
            bundle: None,
            envelope: None,
            open_error,
        };

        match plain {
            Ok(plain) => match serde_json::from_slice::<MutandeBundle>(&plain) {
                Ok(bundle) => OpenedThreadMessage {
                    id: msg.id,
                    thread_id: msg.thread_id,
                    from_user_id: msg.from_user_id,
                    from_handle: msg.from_handle,
                    created_at: msg.created_at,
                    sender_only: msg.sender_only,
                    bundle: Some(bundle),
                    envelope: None,
                    open_error: None,
                },
                Err(_err) if is_blob => {
                    // Raw artifact bytes in R2 — summarize without embedding content.
                    OpenedThreadMessage {
                        id: msg.id,
                        thread_id: msg.thread_id,
                        from_user_id: msg.from_user_id,
                        from_handle: msg.from_handle,
                        created_at: msg.created_at,
                        sender_only: msg.sender_only,
                        bundle: Some(MutandeBundle {
                            subject: Some("blob artifact".into()),
                            notes: Some(format!(
                                "Opened encrypted blob ({} bytes); content not inlined.",
                                plain.len()
                            )),
                            resources: vec![BundleResource {
                                name: "artifact.bin".into(),
                                mime: "application/octet-stream".into(),
                                content: None,
                            }],
                            ..Default::default()
                        }),
                        envelope: None,
                        open_error: None,
                    }
                }
                Err(err) => meta(Some(format!("decode bundle: {err}"))),
            },
            Err(err) => meta(Some(err.to_string())),
        }
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

    pub async fn forward_draft(&self, recipient: &str) -> Result<String> {
        let bundle = self.get_draft_plain();
        if bundle.questions.is_empty()
            && bundle.resource_requests.is_empty()
            && bundle.resources.is_empty()
            && bundle.subject.is_none()
            && bundle.context.is_none()
            && bundle.notes.as_ref().is_none_or(|n| n.trim().is_empty())
        {
            bail!("draft is empty");
        }

        let plain = serde_json::to_vec(&bundle)?;
        let recipients = self.resolve_recipient_pubkeys(recipient).await?;
        let env = self.seal_inline_or_blob(&plain, &recipients).await?;

        let thread_id = if let Some(hub) = self.hub_client() {
            let from_agent = self.from_agent_for_send();
            let resp = hub
                .create_thread(recipient, &env, from_agent.as_deref())
                .await?;
            resp.thread.id
        } else {
            uuid::Uuid::new_v4().to_string()
        };

        let draft_id = self.draft_id.lock().unwrap().take();
        if let Some(hub) = self.hub_client() {
            if let Some(draft_id) = draft_id {
                let _ = hub.delete_draft(&draft_id).await;
            }
        }
        self.clear_draft();

        Ok(thread_id)
    }

    /// Explicit blob send: seal bytes → upload → create thread with blob envelope.
    ///
    /// Seals raw `plaintext` (artifact bytes). Recipient `get_thread` opens and
    /// surfaces a summary bundle (size/name) without inlining ciphertext.
    pub async fn forward_blob(
        &self,
        recipient: &str,
        plaintext: &[u8],
        _subject: Option<&str>,
    ) -> Result<String> {
        if plaintext.is_empty() {
            bail!("blob plaintext empty");
        }
        let recipients = self.resolve_recipient_pubkeys(recipient).await?;
        let env = self.seal_and_upload_blob(plaintext, &recipients).await?;

        if let Some(hub) = self.hub_client() {
            let from_agent = self.from_agent_for_send();
            let resp = hub
                .create_thread(recipient, &env, from_agent.as_deref())
                .await?;
            Ok(resp.thread.id)
        } else {
            Ok(uuid::Uuid::new_v4().to_string())
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
    ) -> Result<()> {
        let plain = serde_json::to_vec(&bundle)?;
        let detail = self.get_thread(thread_id).await?;
        let recipients = self.resolve_reply_recipients(&detail).await?;
        let env = self.seal_inline_or_blob(&plain, &recipients).await?;

        if let Some(hub) = self.hub_client() {
            let from_agent = self.from_agent_for_send();
            hub.reply_to_thread(thread_id, &env, from_agent.as_deref(), to_agent)
                .await?;
        }
        Ok(())
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

    pub fn mark_processed(&self, thread_id: &str) {
        self.processed_threads.lock().unwrap().insert(thread_id.to_string());
    }

    pub fn is_processed(&self, thread_id: &str) -> bool {
        self.processed_threads.lock().unwrap().contains(thread_id)
    }

    async fn resolve_recipient_pubkeys(&self, recipient: &str) -> Result<Vec<DevicePubKey>> {
        let bare = strip_agent_suffix(recipient);
        if is_broadcast_handle(bare) {
            let contacts = self.list_contacts().await?;
            let keys: Vec<DevicePubKey> = contacts
                .iter()
                .filter_map(|c| c.pubkey.as_deref().and_then(pubkey_from_hub_string))
                .collect();
            if keys.is_empty() {
                bail!("no pubkeys for broadcast {recipient}");
            }
            return Ok(keys);
        }

        let contacts = self.list_contacts().await?;
        for contact in &contacts {
            if contact.handle == bare {
                if let Some(pk) = contact
                    .pubkey
                    .as_deref()
                    .and_then(pubkey_from_hub_string)
                {
                    return Ok(vec![pk]);
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
                    return Ok(vec![self.device_public()?]);
                }
            }
        }

        bail!("unknown recipient {recipient}");
    }

    /// Seal replies to `thread.from` only.
    ///
    /// PRD v1: broadcast replies are sender-only (not re-broadcast to `@all` / participants).
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

fn agent_matches_display(display: &str, slug: &str, default_slug: &str) -> bool {
    match agent_suffix(display) {
        Some(s) => s == slug,
        None => slug == default_slug,
    }
}

fn thread_visible_for_agent(
    thread: &ThreadMeta,
    my_user_id: &str,
    slug: &str,
    default_slug: &str,
) -> bool {
    if thread.kind == ThreadKind::Broadcast {
        return slug == default_slug;
    }
    if thread.from_user_id == my_user_id {
        agent_matches_display(&thread.from, slug, default_slug)
    } else {
        agent_matches_display(&thread.audience, slug, default_slug)
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
    use crate::hub_client::{ThreadKind, ThreadStatus};

    #[test]
    fn auth0_resolvers_fall_back_to_builtin_defaults() {
        // Explicit / env take precedence; with neither, use compile-time defaults.
        assert_eq!(
            resolve_auth0_domain(None).unwrap(),
            super::super::auth0_defaults::AUTH0_DOMAIN
        );
        assert_eq!(
            resolve_auth0_client_id(None).unwrap(),
            super::super::auth0_defaults::AUTH0_NATIVE_CLIENT_ID
        );
        // Audience already had a hardcoded fallback; ensure it matches the module.
        let audience = resolve_auth0_audience(None);
        assert!(
            audience == super::super::auth0_defaults::AUTH0_AUDIENCE
                || std::env::var("AUTH0_AUDIENCE").is_ok()
        );
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
            },
            messages: vec![ThreadMessage {
                id: "m1".into(),
                thread_id: "t1".into(),
                from_user_id: "u1".into(),
                from_handle: "alice@acme".into(),
                envelope: env,
                created_at: "2026-01-01T00:00:00Z".into(),
                sender_only: None,
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
            },
            messages: vec![ThreadMessage {
                id: "m-fail".into(),
                thread_id: "t-fail".into(),
                from_user_id: "u1".into(),
                from_handle: "alice@acme".into(),
                envelope: env,
                created_at: "2026-01-01T00:00:00Z".into(),
                sender_only: None,
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
            },
            messages: vec![ThreadMessage {
                id: "m-bad".into(),
                thread_id: "t-bad".into(),
                from_user_id: "u1".into(),
                from_handle: "alice@acme".into(),
                envelope: env,
                created_at: "2026-01-01T00:00:00Z".into(),
                sender_only: None,
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
        let thread_id = state
            .forward_blob("bob@acme", artifact, Some("code drop"))
            .await
            .unwrap();
        assert_eq!(thread_id, "thread-blob-1");

        let env_json = captured_env.lock().unwrap().clone().unwrap();
        assert_eq!(env_json["blob_id"], "blob-e2e-1");
        assert!(env_json["ciphertext"].as_array().unwrap().is_empty());
        assert!(env_json["sha256"].as_str().unwrap().len() == 64);
        assert!(blob_store.lock().unwrap().as_ref().unwrap().len() > 0);

        let env: Envelope = serde_json::from_value(env_json).unwrap();
        let opened = state.open_envelope_maybe_blob(&env).await.unwrap();
        assert_eq!(opened, artifact);
    }
}
