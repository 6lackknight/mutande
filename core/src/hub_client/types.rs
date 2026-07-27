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
    pub audience: String,
    pub org_id: String,
    pub participant_count: u32,
    pub reply_count: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub your_status: Option<YourStatus>,
    pub created_at: String,
    pub updated_at: String,
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
}

/// Org member or synthetic broadcast handle (`@all@org`).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Contact {
    pub handle: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pubkey: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    pub handle: String,
    pub org_id: String,
    pub pubkey: String,
    pub created_at: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MeResponse {
    pub user: User,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegisterRequest {
    pub invite_code: String,
    pub handle: String,
    pub pubkey: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AuthResponse {
    pub user: User,
    pub access_token: String,
    pub refresh_token: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TokenResponse {
    pub access_token: String,
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
pub struct CreateThreadRequest<'a> {
    pub to: &'a str,
    pub envelope: &'a Envelope,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreateThreadResponse {
    pub thread: ThreadMeta,
    pub message_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct ReplyRequest<'a> {
    pub envelope: &'a Envelope,
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

/// Encode a device pubkey for hub register (`pubkey` string field).
pub fn pubkey_to_hub_string(pk: &DevicePubKey) -> String {
    serde_json::to_string(&pk.0).expect("pubkey bytes serialize")
}

/// Decode a hub `User.pubkey` string into a device pubkey when possible.
pub fn pubkey_from_hub_string(s: &str) -> Option<DevicePubKey> {
    let bytes: Vec<u8> = serde_json::from_str(s).ok()?;
    if bytes.len() != 32 {
        return None;
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    Some(DevicePubKey(arr))
}
