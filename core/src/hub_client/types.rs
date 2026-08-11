use serde::{Deserialize, Serialize};

use crate::crypto::{DevicePubKey, Envelope};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ThreadKind {
    Direct,
    Broadcast,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ThreadStatus {
    Open,
    Closed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum YourStatus {
    Pending,
    Replied,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum InboxRole {
    Sender,
    Recipient,
}

/// Hub-visible thread metadata (never includes plaintext content).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ThreadMeta {
    pub id: String,
    pub kind: ThreadKind,
    pub status: ThreadStatus,
    pub from: String,
    pub from_user_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub from_agent_id: Option<String>,
    pub audience: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub audience_agent_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub audience_wire_path: Option<String>,
    pub org_id: String,
    pub participant_count: u32,
    pub reply_count: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub your_status: Option<YourStatus>,
    pub created_at: String,
    pub updated_at: String,
    /// Daemon-filled after local open — author of the latest message (not hub plaintext).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_from: Option<String>,
    /// Daemon-filled after local open — subject for the list title (latest, else OP).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_subject: Option<String>,
    /// Daemon-filled after local open — body preview of the latest message (notes/etc).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_preview: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ThreadMessage {
    pub id: String,
    pub thread_id: String,
    pub from_user_id: String,
    pub from_handle: String,
    pub envelope: Envelope,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sender_only: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_message_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub upvotes: Option<MessageUpvoteSummary>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageUpvote {
    pub agent_id: String,
    pub from_handle: String,
    pub created_at: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageUpvoteSummary {
    pub count: u32,
    pub upvotes: Vec<MessageUpvote>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub your_upvotes: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct ToggleUpvoteRequest<'a> {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from_agent: Option<&'a str>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToggleUpvoteResponse {
    pub upvoted: bool,
    pub upvotes: MessageUpvoteSummary,
}

/// Org member or synthetic broadcast handle (`@all@org`).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Contact {
    pub handle: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pubkey: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub devices: Vec<ContactDevice>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContactDevice {
    pub pubkey: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub platform: Option<String>,
}

/// Onboarded hub user (Auth0-backed).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auth0_sub: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub handle: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub org_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub role: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pubkey: Option<String>,
    pub created_at: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Org {
    pub id: String,
    pub slug: String,
    pub name: String,
    pub created_at: String,
}

/// `GET /v1/me` / `GET /v1/auth/me` (Auth0 Bearer).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MeResponse {
    pub auth0_sub: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
    #[serde(default)]
    pub needs_onboarding: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub onboarded: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub user: Option<User>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub org: Option<Org>,
}

impl MeResponse {
    pub fn is_onboarded(&self) -> bool {
        if let Some(onboarded) = self.onboarded {
            return onboarded;
        }
        !self.needs_onboarding
            && self
                .user
                .as_ref()
                .and_then(|u| u.handle.as_ref())
                .is_some()
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct CreateOrgRequest {
    pub slug: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub handle: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct JoinOrgRequest {
    pub invite_code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub handle: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Agent {
    pub id: String,
    pub user_id: String,
    pub slug: String,
    pub created_at: String,
    /// Hub-assigned: `sidecar` | `mcp`. Absent on pre-L1 rows.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub transport: Option<String>,
    /// Hub-assigned: `private` | `public`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub visibility: Option<String>,
    /// Hub-assigned: `org` | `external` | `enterprise`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trust_tier: Option<String>,
    /// Hub-assigned for mcp transport; null/absent for sidecar.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mcp_endpoint: Option<String>,
    /// Last capability handshake; Flutter maps as last_seen / freshness.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub capabilities_updated_at: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentListResponse {
    pub agents: Vec<Agent>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default_agent_id: Option<String>,
}

/// Preferred transport per display slug (`GET`/`PUT /v1/agents/transport-defaults`).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct AgentTransportPrefs {
    #[serde(default)]
    pub defaults: std::collections::BTreeMap<String, String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct SetTransportDefaultRequest {
    pub slug: String,
    pub transport: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentsForHandleResponse {
    pub agents: Vec<Agent>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct RegisterAgentRequest {
    pub slug: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegisterAgentResponse {
    pub agent: Agent,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct SetDefaultAgentRequest {
    pub agent_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SetDefaultAgentResponse {
    pub agent: Agent,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct RenameAgentRequest {
    pub slug: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RenameAgentResponse {
    pub agent: Agent,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RoutingRule {
    pub match_slug: String,
    pub agent_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RouterConfig {
    pub default_agent_id: Option<String>,
    pub rules: Vec<RoutingRule>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct SetRouterRequest {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub default_agent_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rules: Option<Vec<RoutingRule>>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct RegisterDeviceRequest {
    pub pubkey: String,
    pub platform: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent_slug: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Device {
    pub id: String,
    pub user_id: String,
    pub pubkey: String,
    pub platform: String,
    pub created_at: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegisterDeviceResponse {
    pub device: Device,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ListDevicesResponse {
    pub devices: Vec<Device>,
}

/// Auth0 `/oauth/token` response (native + refresh).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Auth0TokenResponse {
    pub access_token: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub refresh_token: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id_token: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expires_in: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token_type: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ThreadListResponse {
    pub threads: Vec<ThreadMeta>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ThreadDetail {
    pub thread: ThreadMeta,
    pub messages: Vec<ThreadMessage>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContactsResponse {
    pub contacts: Vec<Contact>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct SubmitFeedbackRequest {
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub app_version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub platform: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Feedback {
    pub id: String,
    pub created_at: String,
    pub user_id: String,
    pub handle: String,
    pub org_id: String,
    pub auth0_sub: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
    pub message: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub app_version: Option<String>,
    pub platform: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubmitFeedbackResponse {
    pub feedback: Feedback,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct CreateThreadRequest<'a> {
    pub to: &'a str,
    pub envelope: &'a Envelope,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from_agent: Option<&'a str>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct ReplyRequest<'a> {
    pub envelope: &'a Envelope,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from_agent: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub to_agent: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_message_id: Option<&'a str>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreateThreadResponse {
    pub thread: ThreadMeta,
    pub message_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CloseThreadResponse {
    pub thread: ThreadMeta,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Draft {
    pub id: String,
    pub user_id: String,
    pub org_id: String,
    pub envelope: Envelope,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DraftListResponse {
    pub drafts: Vec<Draft>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DraftResponse {
    pub draft: Draft,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct CreateDraftRequest<'a> {
    pub envelope: &'a Envelope,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BlobUploadUrlRequest {
    pub size_bytes: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content_type: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BlobUploadUrlResponse {
    pub blob_id: String,
    pub upload_url: String,
    pub expires_at: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BlobMeta {
    pub id: String,
    pub org_id: String,
    pub owner_user_id: String,
    pub size_bytes: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content_type: Option<String>,
    pub created_at: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BlobDownloadUrlResponse {
    pub download_url: String,
    pub expires_at: String,
    pub meta: BlobMeta,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ThreadFilter {
    NeedsAction,
    Open,
    Closed,
}

/// Encode a device pubkey for hub device registration (`pubkey` string field).
pub fn pubkey_to_hub_string(pk: &DevicePubKey) -> String {
    serde_json::to_string(&pk.0).expect("pubkey bytes serialize")
}

/// Decode a hub pubkey string into a device pubkey when possible.
pub fn pubkey_from_hub_string(s: &str) -> Option<DevicePubKey> {
    let bytes: Vec<u8> = serde_json::from_str(s).ok()?;
    if bytes.len() != 32 {
        return None;
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    Some(DevicePubKey(arr))
}
