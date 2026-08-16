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
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
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
    /// Thread encryption mode (§4.2). Legacy rows omit → treat as `e2e`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub encryption_mode: Option<String>,
    /// Set after L5 unanimous downgrade — pre-point E2E history stays sealed.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub downgrade_point: Option<ThreadDowngradePoint>,
    /// Set when thread is billed enterprise mail (§7.2) — drives Flutter warn banner.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enterprise_listing_id: Option<String>,
    /// Daemon-filled after local open — author of the latest message (not hub plaintext).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_from: Option<String>,
    /// Daemon-filled after local open — subject for the list title (latest, else OP).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_subject: Option<String>,
    /// Daemon-filled after local open — body preview of the latest message (notes/etc).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_preview: Option<String>,
    /// Hub mirror of post-merge awaiting holders (`{user_id, actor}`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub awaiting: Option<Vec<HubAwaitingEntry>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub collab_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lane_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lane_position: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub assigned_to: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub watchers: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub due_on: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub checklist: Option<Vec<CollabChecklistItem>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub collab_name: Option<String>,
}

/// Card checklist row — same JSON as hub `CollabChecklistItem`.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CollabChecklistItem {
    pub id: String,
    pub text: String,
    #[serde(default)]
    pub done: bool,
}

/// Hub-stored awaiting holder (blind courier mirror of E2E `next_turn`).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct HubAwaitingEntry {
    pub user_id: String,
    pub actor: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ThreadMessage {
    pub id: String,
    pub thread_id: String,
    pub from_user_id: String,
    pub from_handle: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub from_agent_id: Option<String>,
    /// E2E blind envelope — present only for `encryption_mode: e2e`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub envelope: Option<Envelope>,
    /// Hub-readable app_envelope — present only for non-E2E threads.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub app_envelope: Option<AppEnvelopePayload>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content_store: Option<String>,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sender_only: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_message_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub upvotes: Option<MessageUpvoteSummary>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub receipts: Option<MessageReceiptSummary>,
}

/// Hub-readable application-layer payload (directory.prd §4.2.1).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppEnvelopePayload {
    pub version: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub subject: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ping_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub intent: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub questions: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub answers: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resources: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resource_requests: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub in_reply_to: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub next_turn: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub task: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hints: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub due_on: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub checklist: Option<Vec<CollabChecklistItem>>,
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

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageReceipt {
    pub agent_id: String,
    pub from_handle: String,
    pub created_at: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageReceiptSummary {
    pub count: u32,
    pub receipts: Vec<MessageReceipt>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub your_receipts: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct PostReceiptRequest<'a> {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from_agent: Option<&'a str>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PostReceiptResponse {
    pub receipts: MessageReceiptSummary,
}

/// Org member or synthetic broadcast handle (`@all@org`).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Contact {
    pub handle: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pubkey: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub devices: Vec<ContactDevice>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub avatar_url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub external_link_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub linked_at: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thread_id: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContactDevice {
    pub pubkey: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub platform: Option<String>,
}

/// Alice's pairing PIN + QR URI (`mutande://pair?…`).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PairingPin {
    pub pin: String,
    pub handle: String,
    pub expires_at: String,
    pub qr_uri: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PairingPinGetResponse {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pin: Option<PairingPin>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PairRequest {
    pub id: String,
    pub requester_user_id: String,
    pub requester_handle: String,
    pub target_user_id: String,
    pub target_handle: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub intro: Option<String>,
    pub status: String,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resolved_at: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct SubmitPairRequest {
    pub handle: String,
    pub pin: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub intro: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PairRequestResponse {
    pub request: PairRequest,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PendingPairRequests {
    pub incoming: Vec<PairRequest>,
    pub outgoing: Vec<PairRequest>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ApprovePairResponse {
    pub contact: Contact,
    pub thread: ThreadMeta,
    pub request: PairRequest,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct UnpairResponse {
    pub ok: bool,
    #[serde(default)]
    pub closed_thread_ids: Vec<String>,
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

/// Hub warn-banner payload for public enterprise listings (§7.2).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct EnterpriseWarnBanner {
    pub trust_tier: String,
    pub message: String,
}

/// Published registry listing + warn payload (`GET /v1/registry/listing/:idOrAddress`).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistryListingPublic {
    pub listing: RegistryListing,
    pub warn: EnterpriseWarnBanner,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegistryListing {
    pub id: String,
    pub address: String,
    pub agent_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trust_tier: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default_agent_id: Option<String>,
    /// slug → preferred transport (`sidecar` | `mcp`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub transport_defaults: Option<std::collections::BTreeMap<String, String>>,
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

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ThreadListResponse {
    pub threads: Vec<ThreadMeta>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ThreadDowngradePoint {
    pub message_id: String,
    #[serde(default)]
    pub approvers: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ThreadDowngradeProposal {
    pub id: String,
    pub thread_id: String,
    pub proposed_agent_id: String,
    pub proposed_slug: String,
    pub proposer_user_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub proposer_agent_id: Option<String>,
    pub status: String,
    #[serde(default)]
    pub required_approvers: Vec<String>,
    #[serde(default)]
    pub approvals: Vec<String>,
    #[serde(default)]
    pub denials: Vec<String>,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resolved_at: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub divider_message_id: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ProposeDowngradeResponse {
    pub proposal: ThreadDowngradeProposal,
    pub prompt: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ApproveDowngradeResponse {
    pub proposal: ThreadDowngradeProposal,
    pub thread: ThreadMeta,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PendingDowngradeProposals {
    pub proposals: Vec<ThreadDowngradeProposal>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ThreadDetail {
    pub thread: ThreadMeta,
    pub messages: Vec<ThreadMessage>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pending_downgrade: Option<ThreadDowngradeProposal>,
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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub envelope: Option<&'a Envelope>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub app_envelope: Option<&'a AppEnvelopePayload>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from_agent: Option<&'a str>,
    /// Post-merge awaiting mirror computed by sender core.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub turns: Option<&'a [HubAwaitingEntry]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub collab_id: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lane_id: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub assigned_to: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<&'a [String]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub due_on: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub checklist: Option<&'a [CollabChecklistItem]>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct ReplyRequest<'a> {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub envelope: Option<&'a Envelope>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub app_envelope: Option<&'a AppEnvelopePayload>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from_agent: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub to_agent: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_message_id: Option<&'a str>,
    /// Post-merge awaiting mirror computed by sender core.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub turns: Option<&'a [HubAwaitingEntry]>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct CreateThreadResponse {
    pub thread: ThreadMeta,
    pub message_id: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
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

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CollabLane {
    pub id: String,
    pub name: String,
    pub position: i64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CollabRosterEntry {
    #[serde(default)]
    pub user_id: String,
    pub agent_id: String,
    pub address: String,
    #[serde(default)]
    pub transport: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CollabSteerer {
    pub user_id: String,
    pub handle: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CollabPendingMembership {
    pub kind: String,
    #[serde(default)]
    pub handle: Option<String>,
    #[serde(default)]
    pub address: Option<String>,
    pub cause_address: String,
    pub proposed_by: String,
    #[serde(default)]
    pub approved_by: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CollabLearning {
    pub id: String,
    #[serde(default, alias = "at")]
    pub created_at: String,
    #[serde(default)]
    pub from_handle: Option<String>,
    #[serde(default)]
    pub from_agent: Option<String>,
    #[serde(default)]
    pub from_agent_id: Option<String>,
    #[serde(default)]
    pub notes: Option<String>,
    #[serde(default)]
    pub sealed: Option<bool>,
}

/// Hub board card — subset of thread meta (lane + identity). Not a full [ThreadMeta].
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct CollabCardSummary {
    pub id: String,
    #[serde(default)]
    pub lane_id: Option<String>,
    #[serde(default)]
    pub lane_position: Option<f64>,
    #[serde(default)]
    pub assigned_to: Option<String>,
    #[serde(default)]
    pub watchers: Option<Vec<String>>,
    #[serde(default)]
    pub tags: Option<Vec<String>>,
    #[serde(default)]
    pub due_on: Option<String>,
    #[serde(default)]
    pub checklist: Option<Vec<CollabChecklistItem>>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub from: Option<String>,
    #[serde(default)]
    pub audience: Option<String>,
    #[serde(default)]
    pub updated_at: Option<String>,
    #[serde(default)]
    pub your_status: Option<String>,
    #[serde(default)]
    pub last_subject: Option<String>,
}

fn default_artifact_kind() -> String {
    "file".into()
}

/// Collab artifact: hub-persisted (file envelope/content or link URL) or
/// device-local harvest from a card thread after open.
///
/// `kind` defaults to `file` so older harvested payloads keep parsing.
/// Hub never receives local `path`; the sidecar sets it after decrypt.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CollabArtifactSummary {
    #[serde(default = "default_artifact_kind")]
    pub kind: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub mime: String,
    #[serde(default)]
    pub size: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub envelope: Option<crate::crypto::Envelope>,
    #[serde(default)]
    pub thread_id: String,
    #[serde(default)]
    pub message_id: String,
    #[serde(default)]
    pub card_title: String,
    #[serde(default)]
    pub from_handle: String,
    #[serde(default)]
    pub created_at: String,
}

impl CollabArtifactSummary {
    pub fn is_link(&self) -> bool {
        self.kind.eq_ignore_ascii_case("link")
    }

    pub fn display_label(&self) -> String {
        if let Some(label) = self.label.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
            return label.to_string();
        }
        if self.is_link() {
            return self
                .url
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .unwrap_or("link")
                .to_string();
        }
        if !self.name.trim().is_empty() {
            return self.name.clone();
        }
        "file".into()
    }

    /// Drop sealed payload after local open — Flutter only needs path/content.
    pub fn strip_sealed(&mut self) {
        self.envelope = None;
        if self.path.as_deref().map(str::trim).filter(|s| !s.is_empty()).is_some() {
            self.content = None;
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Collab {
    pub id: String,
    pub org_id: String,
    pub name: String,
    pub created_by: String,
    pub created_at: String,
    #[serde(default)]
    pub updated_at: String,
    #[serde(default)]
    pub schema_version: i64,
    pub encryption_mode: String,
    #[serde(default)]
    pub instructions: Option<String>,
    #[serde(default)]
    pub lists: Vec<CollabLane>,
    #[serde(default)]
    pub roster: Vec<CollabRosterEntry>,
    #[serde(default)]
    pub memory_thread_id: String,
    #[serde(default)]
    pub downgrade_point: Option<serde_json::Value>,
    /// Missing or "open" = active. "archived" boards are frozen.
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub pending_membership: Option<CollabPendingMembership>,
    #[serde(default)]
    pub card_count: u64,
    #[serde(default)]
    pub open: u64,
    #[serde(default)]
    pub backlog: u64,
    #[serde(default)]
    pub doing: u64,
    #[serde(default)]
    pub done: u64,
    #[serde(default)]
    pub needs_you: u64,
    #[serde(default)]
    pub last_card_updated_at: Option<String>,
    #[serde(default)]
    pub steerers: Vec<CollabSteerer>,
    #[serde(default)]
    pub cards: Vec<CollabCardSummary>,
    #[serde(default)]
    pub learnings: Vec<CollabLearning>,
    /// Hub-persisted plus sidecar harvest. JSON null/omitted → [].
    #[serde(default, deserialize_with = "null_as_default")]
    pub artifacts: Vec<CollabArtifactSummary>,
}

impl Collab {
    pub fn is_archived(&self) -> bool {
        self.status.as_deref() == Some("archived")
    }
}

fn null_as_default<'de, D, T>(deserializer: D) -> Result<T, D::Error>
where
    D: serde::Deserializer<'de>,
    T: Default + serde::Deserialize<'de>,
{
    Ok(Option::<T>::deserialize(deserializer)?.unwrap_or_default())
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct CollabActivityDay {
    pub date: String,
    #[serde(default)]
    pub count: u64,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct CollabLaneTotals {
    #[serde(default)]
    pub backlog: u64,
    #[serde(default)]
    pub doing: u64,
    #[serde(default)]
    pub done: u64,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct CollabPortfolioTotals {
    #[serde(default)]
    pub collabs: u64,
    #[serde(default)]
    pub open: u64,
    #[serde(default)]
    pub doing: u64,
    #[serde(default)]
    pub needs_you: u64,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct CollabPortfolioRecent {
    #[serde(default)]
    pub thread_id: String,
    #[serde(default)]
    pub collab_id: String,
    #[serde(default)]
    pub collab_name: String,
    #[serde(default)]
    pub from: String,
    #[serde(default)]
    pub audience: String,
    #[serde(default)]
    pub last_subject: Option<String>,
    #[serde(default)]
    pub updated_at: String,
    #[serde(default)]
    pub needs_you: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct CollabPortfolio {
    #[serde(default)]
    pub activity: Vec<CollabActivityDay>,
    #[serde(default)]
    pub lane_totals: CollabLaneTotals,
    #[serde(default)]
    pub totals: CollabPortfolioTotals,
    #[serde(default)]
    pub recent: Vec<CollabPortfolioRecent>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ListCollabsResponse {
    pub collabs: Vec<Collab>,
    #[serde(default)]
    pub portfolio: CollabPortfolio,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct CollabResponse {
    pub collab: Collab,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct CreateCollabRequest<'a> {
    pub name: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub steerer_handles: Option<&'a [String]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub roster_addresses: Option<&'a [String]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instructions: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub artifacts: Option<&'a [CollabArtifactSummary]>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct SetLaneRequest<'a> {
    pub thread_id: &'a str,
    pub lane_id: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub before_thread_id: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub after_thread_id: Option<&'a str>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct AddLearningRequest<'a> {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from_agent: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from_agent_id: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub envelope: Option<&'a Envelope>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct UpdateInstructionsRequest<'a> {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub instructions: Option<&'a str>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct AddCollabArtifactsRequest<'a> {
    pub artifacts: &'a [CollabArtifactSummary],
}

#[cfg(test)]
mod collab_artifact_tests {
    use super::*;

    #[test]
    fn omitted_kind_is_file_and_null_artifacts_default_empty() {
        let collab: Collab = serde_json::from_value(serde_json::json!({
            "id": "c1",
            "org_id": "o1",
            "name": "Launch",
            "created_by": "u1",
            "created_at": "2026-08-16T12:00:00Z",
            "encryption_mode": "e2e",
        }))
        .unwrap();
        assert!(collab.artifacts.is_empty());

        let harvested: CollabArtifactSummary = serde_json::from_value(serde_json::json!({
            "name": "brief.md",
            "mime": "text/markdown",
            "thread_id": "t1",
            "message_id": "m1",
            "card_title": "Triage",
            "from_handle": "alice@acme",
            "created_at": "2026-08-16T12:00:00Z",
        }))
        .unwrap();
        assert_eq!(harvested.kind, "file");
        assert!(!harvested.is_link());
        assert_eq!(harvested.display_label(), "brief.md");
    }

    #[test]
    fn link_and_file_round_trip() {
        let link = CollabArtifactSummary {
            kind: "link".into(),
            label: Some("Staging".into()),
            url: Some("https://staging.example.com".into()),
            name: String::new(),
            mime: String::new(),
            size: None,
            path: None,
            content: None,
            envelope: None,
            thread_id: String::new(),
            message_id: String::new(),
            card_title: String::new(),
            from_handle: "alice@acme".into(),
            created_at: "2026-08-16T12:00:00Z".into(),
        };
        let v = serde_json::to_value(&link).unwrap();
        assert_eq!(v["kind"], "link");
        assert_eq!(v["url"], "https://staging.example.com");
        assert!(v.get("path").is_none());
        let back: CollabArtifactSummary = serde_json::from_value(v).unwrap();
        assert!(back.is_link());
        assert_eq!(back.display_label(), "Staging");

        let file: CollabArtifactSummary = serde_json::from_value(serde_json::json!({
            "kind": "file",
            "name": "shot.png",
            "mime": "image/png",
            "size": 12,
            "path": "/tmp/shot.png",
        }))
        .unwrap();
        assert!(!file.is_link());
        assert_eq!(file.display_label(), "shot.png");
        assert_eq!(file.path.as_deref(), Some("/tmp/shot.png"));
    }

    #[test]
    fn artifacts_json_null_is_empty_vec() {
        let collab: Collab = serde_json::from_value(serde_json::json!({
            "id": "c1",
            "org_id": "o1",
            "name": "Launch",
            "created_by": "u1",
            "created_at": "2026-08-16T12:00:00Z",
            "encryption_mode": "e2e",
            "artifacts": null,
        }))
        .unwrap();
        assert!(collab.artifacts.is_empty());
    }
}
