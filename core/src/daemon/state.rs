use std::collections::HashSet;
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result, bail};
use crypto_box::aead::OsRng;
use crypto_box::SecretKey;
use serde::{Deserialize, Serialize};

use crate::crypto::{
    DevicePubKey, DeviceSecretKey, Envelope, IdentityStore, MemoryStore, StoreError, open, seal,
};

#[cfg(target_os = "macos")]
use crate::crypto::KeychainIdentityStore;
use crate::hub_client::{
    Contact, HubClient, ThreadDetail, ThreadFilter, ThreadMessage, ThreadMeta,
    pubkey_from_hub_string,
};

use super::config::{DaemonConfig, config_path, load_config, save_config_at};

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

/// Result of invite/register onboarding.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct OnboardResult {
    pub handle: String,
    pub org_id: String,
}

/// Daemon + hub session status (no secrets).
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct StatusResult {
    pub configured: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hub_url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub handle: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub org_id: Option<String>,
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
}

impl DaemonState {
    pub fn bootstrap() -> Result<Self> {
        let loaded = load_config().unwrap_or_default();
        let identity = bootstrap_identity()?;
        let config = Arc::new(Mutex::new(loaded.clone()));
        let hub = match (&loaded.hub_url, &loaded.jwt) {
            (Some(url), Some(token)) => Some(make_hub_client(
                url,
                token,
                loaded.refresh_token.clone(),
                Arc::clone(&config),
                None,
            )?),
            _ => None,
        };

        Ok(Self {
            config,
            config_path: None,
            identity,
            hub: Mutex::new(hub),
            draft: Mutex::new(MutandeBundle::default()),
            draft_id: Mutex::new(None),
            processed_threads: Mutex::new(HashSet::new()),
        })
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
        })
    }

    fn hub_client(&self) -> Option<HubClient> {
        self.hub.lock().unwrap().clone()
    }

    /// Register device with hub via invite; persist jwt + hub_url.
    pub async fn register(
        &self,
        invite_code: &str,
        handle: &str,
        hub_url: &str,
    ) -> Result<OnboardResult> {
        let invite_code = invite_code.trim();
        let handle = handle.trim();
        let hub_url = hub_url.trim().trim_end_matches('/');
        if invite_code.is_empty() {
            bail!("missing param: invite_code");
        }
        if handle.is_empty() {
            bail!("missing param: handle");
        }
        if hub_url.is_empty() {
            bail!("missing param: hub_url");
        }

        let pubkey = self.device_public()?;
        // Register is unauthenticated; empty JWT is fine for HubClient.
        let client = HubClient::new(crate::hub_client::HubConfig::new(hub_url, ""))?;
        let auth = client.register(invite_code, handle, &pubkey).await?;

        let mut cfg = self.config.lock().unwrap();
        cfg.hub_url = Some(hub_url.to_string());
        cfg.jwt = Some(auth.access_token.clone());
        cfg.refresh_token = Some(auth.refresh_token.clone());
        let to_save = cfg.clone();
        drop(cfg);

        let path = self
            .config_path
            .clone()
            .unwrap_or_else(config_path);
        save_config_at(&path, &to_save)?;

        let hub = make_hub_client(
            hub_url,
            &auth.access_token,
            Some(auth.refresh_token),
            Arc::clone(&self.config),
            self.config_path.clone(),
        )?;
        *self.hub.lock().unwrap() = Some(hub);

        Ok(OnboardResult {
            handle: auth.user.handle,
            org_id: auth.user.org_id,
        })
    }

    /// Whether JWT/hub are configured; when possible, resolve handle via hub `/me`.
    pub async fn get_status(&self) -> Result<StatusResult> {
        let cfg = self.config.lock().unwrap().clone();
        let configured = cfg.hub_url.is_some() && cfg.jwt.is_some();
        if !configured {
            return Ok(StatusResult {
                configured: false,
                hub_url: cfg.hub_url,
                handle: None,
                org_id: None,
            });
        }

        if let Some(hub) = self.hub_client() {
            if let Ok(user) = hub.me().await {
                return Ok(StatusResult {
                    configured: true,
                    hub_url: cfg.hub_url,
                    handle: Some(user.handle),
                    org_id: Some(user.org_id),
                });
            }
        }

        Ok(StatusResult {
            configured: true,
            hub_url: cfg.hub_url,
            handle: None,
            org_id: None,
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
            return hub.list_threads(filter).await;
        }
        Ok(vec![])
    }

    pub async fn get_thread(&self, thread_id: &str) -> Result<OpenedThreadDetail> {
        let Some(hub) = self.hub_client() else {
            bail!("hub not configured");
        };
        let detail = hub.get_thread(thread_id).await?;
        Ok(self.open_thread_detail(detail))
    }

    /// Attempt to open each message envelope; succeed with `bundle`, else `open_error` + meta only
    /// (never return ciphertext/wraps into agent/MCP context).
    pub fn open_thread_detail(&self, detail: ThreadDetail) -> OpenedThreadDetail {
        let messages = detail
            .messages
            .into_iter()
            .map(|msg| self.open_thread_message(msg))
            .collect();
        OpenedThreadDetail {
            thread: detail.thread,
            messages,
        }
    }

    fn open_thread_message(&self, msg: ThreadMessage) -> OpenedThreadMessage {
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

        match self.open_envelope(&msg.envelope) {
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
                Err(err) => meta(Some(format!("decode bundle: {err}"))),
            },
            Err(err) => meta(Some(err.to_string())),
        }
    }

    pub async fn forward_draft(&self, recipient: &str) -> Result<String> {
        let bundle = self.get_draft_plain();
        if bundle.questions.is_empty()
            && bundle.resource_requests.is_empty()
            && bundle.resources.is_empty()
            && bundle.subject.is_none()
            && bundle.context.is_none()
        {
            bail!("draft is empty");
        }

        let plain = serde_json::to_vec(&bundle)?;
        let recipients = self.resolve_recipient_pubkeys(recipient).await?;
        let env = seal(&plain, &recipients).map_err(|e| anyhow::anyhow!("{e}"))?;

        let thread_id = if let Some(hub) = self.hub_client() {
            let resp = hub.create_thread(recipient, &env).await?;
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

    pub async fn reply_to_thread(&self, thread_id: &str, bundle: MutandeBundle) -> Result<()> {
        let plain = serde_json::to_vec(&bundle)?;
        let detail = self.get_thread(thread_id).await?;
        let recipients = self.resolve_reply_recipients(&detail).await?;
        let env = seal(&plain, &recipients).map_err(|e| anyhow::anyhow!("{e}"))?;

        if let Some(hub) = self.hub_client() {
            hub.reply_to_thread(thread_id, &env).await?;
        }
        Ok(())
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
        if recipient.starts_with("@all@") {
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
            if contact.handle == recipient {
                if let Some(pk) = contact
                    .pubkey
                    .as_deref()
                    .and_then(pubkey_from_hub_string)
                {
                    return Ok(vec![pk]);
                }
                bail!("contact {recipient} has no pubkey");
            }
        }

        if let Some(hub) = self.hub_client() {
            if let Ok(me) = hub.me().await {
                if me.handle == recipient {
                    if let Some(pk) = pubkey_from_hub_string(&me.pubkey) {
                        return Ok(vec![pk]);
                    }
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
        let sender = detail.thread.from.clone();
        self.resolve_recipient_pubkeys(&sender).await
    }

}

/// Hub client that persists refreshed JWTs into config.json + shared in-memory config.
fn make_hub_client(
    hub_url: &str,
    access_token: &str,
    refresh_token: Option<String>,
    config: Arc<Mutex<DaemonConfig>>,
    config_path_override: Option<PathBuf>,
) -> Result<HubClient> {
    let path = config_path_override.unwrap_or_else(config_path);
    let on_token = move |new_jwt: String| {
        if let Ok(mut guard) = config.lock() {
            guard.jwt = Some(new_jwt.clone());
            let snapshot = guard.clone();
            drop(guard);
            if let Err(err) = save_config_at(&path, &snapshot) {
                tracing::error!(error = %err, "failed to persist refreshed jwt");
            }
        }
    };

    HubClient::new(
        crate::hub_client::HubConfig::new(hub_url, access_token)
            .with_refresh_token(refresh_token)
            .with_on_access_token(on_token),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hub_client::{ThreadKind, ThreadStatus};

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
                audience: "bob@acme".into(),
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
                audience: "bob@acme".into(),
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
}
