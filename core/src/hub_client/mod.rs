//! HTTPS client for Mutande hub (ciphertext in/out only).

mod types;

pub use types::*;

use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};
use reqwest::{Client, StatusCode};
use serde::de::DeserializeOwned;
use serde::Serialize;

use crate::crypto::{DevicePubKey, Envelope};

#[derive(Clone)]
pub struct HubConfig {
    pub hub_url: String,
    pub token: String,
    pub refresh_token: Option<String>,
    /// Invoked with the new access token after a successful refresh (persist to config).
    #[allow(clippy::type_complexity)]
    pub on_access_token: Option<Arc<dyn Fn(String) + Send + Sync>>,
}

impl std::fmt::Debug for HubConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HubConfig")
            .field("hub_url", &self.hub_url)
            .field("token", &"***")
            .field("refresh_token", &self.refresh_token.as_ref().map(|_| "***"))
            .field("on_access_token", &self.on_access_token.is_some())
            .finish()
    }
}

impl HubConfig {
    pub fn new(hub_url: impl Into<String>, token: impl Into<String>) -> Self {
        Self {
            hub_url: hub_url.into().trim_end_matches('/').to_string(),
            token: token.into(),
            refresh_token: None,
            on_access_token: None,
        }
    }

    pub fn with_refresh_token(mut self, refresh_token: Option<String>) -> Self {
        self.refresh_token = refresh_token;
        self
    }

    pub fn with_on_access_token(
        mut self,
        cb: impl Fn(String) + Send + Sync + 'static,
    ) -> Self {
        self.on_access_token = Some(Arc::new(cb));
        self
    }
}

#[derive(Clone)]
pub struct HubClient {
    client: Client,
    hub_url: String,
    token: Arc<Mutex<String>>,
    refresh_token: Option<String>,
    on_access_token: Option<Arc<dyn Fn(String) + Send + Sync>>,
}

impl HubClient {
    pub fn new(config: HubConfig) -> Result<Self> {
        let client = Client::builder()
            .user_agent("mutande-core/0.1")
            .build()
            .context("build HTTP client")?;
        Ok(Self {
            client,
            hub_url: config.hub_url,
            token: Arc::new(Mutex::new(config.token)),
            refresh_token: config.refresh_token,
            on_access_token: config.on_access_token,
        })
    }

    pub fn hub_url(&self) -> &str {
        &self.hub_url
    }

    pub fn access_token(&self) -> String {
        self.token.lock().unwrap().clone()
    }

    pub async fn register(
        &self,
        invite_code: &str,
        handle: &str,
        pubkey: &DevicePubKey,
    ) -> Result<AuthResponse> {
        let body = RegisterRequest {
            invite_code: invite_code.to_string(),
            handle: handle.to_string(),
            pubkey: pubkey_to_hub_string(pubkey),
        };
        self.post_json("/v1/auth/register", &body, false).await
    }

    pub async fn exchange_refresh_token(&self, refresh_token: &str) -> Result<TokenResponse> {
        #[derive(Serialize)]
        struct Body<'a> {
            refresh_token: &'a str,
        }
        // Unauthenticated — must not go through the 401-retry loop.
        self.post_json_no_retry("/v1/auth/token", &Body { refresh_token }, false)
            .await
    }

    fn set_access_token(&self, token: String) {
        *self.token.lock().unwrap() = token.clone();
        if let Some(cb) = &self.on_access_token {
            cb(token);
        }
    }

    /// On 401 with a stored refresh token: refresh once, update access token, return true.
    async fn try_refresh_after_unauthorized(&self) -> bool {
        let Some(refresh) = self.refresh_token.clone() else {
            return false;
        };
        match self.exchange_refresh_token(&refresh).await {
            Ok(tok) => {
                self.set_access_token(tok.access_token);
                true
            }
            Err(err) => {
                tracing::warn!(error = %err, "hub token refresh failed");
                false
            }
        }
    }

    pub async fn me(&self) -> Result<User> {
        let resp: MeResponse = self.get_json("/v1/auth/me").await?;
        Ok(resp.user)
    }

    pub async fn list_contacts(&self) -> Result<Vec<Contact>> {
        let resp: ContactsResponse = self.get_json("/v1/contacts").await?;
        Ok(resp.contacts)
    }

    pub async fn list_threads(&self, filter: Option<ThreadFilter>) -> Result<Vec<ThreadMeta>> {
        let path = match filter {
            Some(ThreadFilter::NeedsAction) => "/v1/threads?filter=needs_action".to_string(),
            Some(ThreadFilter::Open) => "/v1/threads?filter=open".to_string(),
            Some(ThreadFilter::Closed) => "/v1/threads?filter=closed".to_string(),
            None => "/v1/threads".to_string(),
        };
        let resp: ThreadListResponse = self.get_json(&path).await?;
        Ok(resp.threads)
    }

    pub async fn create_thread(&self, to: &str, envelope: &Envelope) -> Result<CreateThreadResponse> {
        let body = CreateThreadRequest { to, envelope };
        self.post_json("/v1/threads", &body, true).await
    }

    pub async fn get_thread(&self, thread_id: &str) -> Result<ThreadDetail> {
        self.get_json(&format!("/v1/threads/{thread_id}")).await
    }

    pub async fn reply_to_thread(&self, thread_id: &str, envelope: &Envelope) -> Result<()> {
        let body = ReplyRequest { envelope };
        let _: serde_json::Value = self
            .post_json(
                &format!("/v1/threads/{thread_id}/replies"),
                &body,
                true,
            )
            .await?;
        Ok(())
    }

    pub async fn close_thread(&self, thread_id: &str) -> Result<ThreadMeta> {
        let resp: CloseThreadResponse = self
            .post_json(
                &format!("/v1/threads/{thread_id}/close"),
                &serde_json::json!({}),
                true,
            )
            .await?;
        Ok(resp.thread)
    }

    pub async fn list_drafts(&self) -> Result<Vec<Draft>> {
        let resp: DraftListResponse = self.get_json("/v1/drafts").await?;
        Ok(resp.drafts)
    }

    pub async fn create_draft(&self, envelope: &Envelope) -> Result<Draft> {
        let body = CreateDraftRequest { envelope };
        let resp: DraftResponse = self.post_json("/v1/drafts", &body, true).await?;
        Ok(resp.draft)
    }

    pub async fn get_draft(&self, draft_id: &str) -> Result<Draft> {
        let resp: DraftResponse = self
            .get_json(&format!("/v1/drafts/{draft_id}"))
            .await?;
        Ok(resp.draft)
    }

    pub async fn update_draft(&self, draft_id: &str, envelope: &Envelope) -> Result<Draft> {
        let body = CreateDraftRequest { envelope };
        let resp: DraftResponse = self
            .put_json(&format!("/v1/drafts/{draft_id}"), &body)
            .await?;
        Ok(resp.draft)
    }

    pub async fn delete_draft(&self, draft_id: &str) -> Result<()> {
        let path = format!("/v1/drafts/{draft_id}");
        let mut attempted_refresh = false;
        loop {
            let token = self.access_token();
            let resp = self
                .client
                .delete(self.url(&path))
                .bearer_auth(&token)
                .send()
                .await
                .with_context(|| format!("DELETE {path}"))?;

            if resp.status().is_success() || resp.status() == StatusCode::NOT_FOUND {
                return Ok(());
            }
            if resp.status() == StatusCode::UNAUTHORIZED
                && !attempted_refresh
                && self.try_refresh_after_unauthorized().await
            {
                attempted_refresh = true;
                continue;
            }
            return Err(hub_error(
                resp.status(),
                resp.text().await.unwrap_or_default(),
            ));
        }
    }

    /// Most recently updated draft, if any (max `updated_at`).
    pub async fn primary_draft(&self) -> Result<Option<Draft>> {
        let drafts = self.list_drafts().await?;
        Ok(drafts
            .into_iter()
            .max_by(|a, b| a.updated_at.cmp(&b.updated_at)))
    }

    /// Create or update the user's latest draft envelope.
    pub async fn upsert_primary_draft(&self, envelope: &Envelope) -> Result<Draft> {
        if let Some(existing) = self.primary_draft().await? {
            self.update_draft(&existing.id, envelope).await
        } else {
            self.create_draft(envelope).await
        }
    }

    pub async fn blob_upload_url(
        &self,
        size_bytes: u64,
        content_type: Option<&str>,
    ) -> Result<BlobUploadUrlResponse> {
        let body = BlobUploadUrlRequest {
            size_bytes,
            content_type: content_type.map(str::to_string),
        };
        self.post_json("/v1/blobs/upload-url", &body, true).await
    }

    pub async fn blob_download_url(&self, blob_id: &str) -> Result<BlobDownloadUrlResponse> {
        self.post_json(
            &format!("/v1/blobs/{blob_id}/download-url"),
            &serde_json::json!({}),
            true,
        )
        .await
    }

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.hub_url, path)
    }

    async fn get_json<T: DeserializeOwned>(&self, path: &str) -> Result<T> {
        let mut attempted_refresh = false;
        loop {
            let token = self.access_token();
            let resp = self
                .client
                .get(self.url(path))
                .bearer_auth(&token)
                .send()
                .await
                .with_context(|| format!("GET {path}"))?;

            if resp.status().is_success() {
                return resp
                    .json()
                    .await
                    .with_context(|| format!("decode GET {path}"));
            }
            if resp.status() == StatusCode::UNAUTHORIZED
                && !attempted_refresh
                && self.try_refresh_after_unauthorized().await
            {
                attempted_refresh = true;
                continue;
            }
            return Err(hub_error(
                resp.status(),
                resp.text().await.unwrap_or_default(),
            ));
        }
    }

    async fn post_json<T, B>(&self, path: &str, body: &B, auth: bool) -> Result<T>
    where
        T: DeserializeOwned,
        B: Serialize + ?Sized,
    {
        let mut attempted_refresh = false;
        loop {
            match self.post_json_no_retry(path, body, auth).await {
                Ok(v) => return Ok(v),
                Err(err) if auth && !attempted_refresh && is_unauthorized(&err) => {
                    if self.try_refresh_after_unauthorized().await {
                        attempted_refresh = true;
                        continue;
                    }
                    return Err(err);
                }
                Err(err) => return Err(err),
            }
        }
    }

    async fn post_json_no_retry<T, B>(&self, path: &str, body: &B, auth: bool) -> Result<T>
    where
        T: DeserializeOwned,
        B: Serialize + ?Sized,
    {
        let mut req = self.client.post(self.url(path)).json(body);
        if auth {
            req = req.bearer_auth(&self.access_token());
        }
        let resp = req.send().await.with_context(|| format!("POST {path}"))?;

        if resp.status().is_success() {
            resp.json()
                .await
                .with_context(|| format!("decode POST {path}"))
        } else {
            Err(hub_error(
                resp.status(),
                resp.text().await.unwrap_or_default(),
            ))
        }
    }

    async fn put_json<T, B>(&self, path: &str, body: &B) -> Result<T>
    where
        T: DeserializeOwned,
        B: Serialize + ?Sized,
    {
        let mut attempted_refresh = false;
        loop {
            let token = self.access_token();
            let resp = self
                .client
                .put(self.url(path))
                .json(body)
                .bearer_auth(&token)
                .send()
                .await
                .with_context(|| format!("PUT {path}"))?;

            if resp.status().is_success() {
                return resp
                    .json()
                    .await
                    .with_context(|| format!("decode PUT {path}"));
            }
            if resp.status() == StatusCode::UNAUTHORIZED
                && !attempted_refresh
                && self.try_refresh_after_unauthorized().await
            {
                attempted_refresh = true;
                continue;
            }
            return Err(hub_error(
                resp.status(),
                resp.text().await.unwrap_or_default(),
            ));
        }
    }
}

fn hub_error(status: StatusCode, body: String) -> anyhow::Error {
    if body.is_empty() {
        anyhow::anyhow!("hub error {status}")
    } else {
        anyhow::anyhow!("hub error {status}: {body}")
    }
}

fn is_unauthorized(err: &anyhow::Error) -> bool {
    err.to_string().contains("hub error 401")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::{DevicePubKey, Wrap};

    fn sample_envelope() -> Envelope {
        Envelope {
            version: 1,
            content_nonce: [0u8; 12],
            ciphertext: vec![1, 2, 3],
            wraps: vec![Wrap {
                recipient: DevicePubKey([0u8; 32]),
                ephemeral_public: DevicePubKey([1u8; 32]),
                boxed_cek: vec![4, 5],
            }],
            blob_id: None,
            sha256: None,
        }
    }

    #[test]
    fn hub_config_trims_trailing_slash() {
        let cfg = HubConfig::new("https://hub.example.com/", "tok");
        assert_eq!(cfg.hub_url, "https://hub.example.com");
    }

    #[test]
    fn register_request_uses_hub_field_names() {
        let req = RegisterRequest {
            invite_code: "inv".into(),
            handle: "alice@acme".into(),
            pubkey: pubkey_to_hub_string(&DevicePubKey([7u8; 32])),
        };
        let json = serde_json::to_value(&req).unwrap();
        assert_eq!(json["invite_code"], "inv");
        assert_eq!(json["handle"], "alice@acme");
        assert!(json.get("invite_token").is_none());
        assert!(json.get("device_pubkey").is_none());
    }

    #[test]
    fn create_thread_request_uses_to_not_recipient() {
        let env = sample_envelope();
        let req = CreateThreadRequest {
            to: "bob@acme",
            envelope: &env,
        };
        let json = serde_json::to_value(&req).unwrap();
        assert_eq!(json["to"], "bob@acme");
        assert!(json.get("recipient").is_none());
        assert_eq!(json["envelope"]["version"], 1);
        assert!(json["envelope"]["content_nonce"].is_array());
    }

    #[test]
    fn reply_request_wraps_envelope_object() {
        let env = sample_envelope();
        let req = ReplyRequest { envelope: &env };
        let json = serde_json::to_value(&req).unwrap();
        assert!(json["envelope"]["wraps"].is_array());
    }

    #[test]
    fn contacts_response_deserializes_handle_and_pubkey() {
        let json = r#"{"contacts":[
            {"handle":"@all@acme","pubkey":null},
            {"handle":"bob@acme","pubkey":"[1,2,3]"}
        ]}"#;
        let resp: ContactsResponse = serde_json::from_str(json).unwrap();
        assert_eq!(resp.contacts.len(), 2);
        assert_eq!(resp.contacts[0].handle, "@all@acme");
        assert!(resp.contacts[0].pubkey.is_none());
        assert_eq!(resp.contacts[1].handle, "bob@acme");
        assert_eq!(resp.contacts[1].pubkey.as_deref(), Some("[1,2,3]"));
    }

    #[test]
    fn thread_detail_deserializes_thread_and_messages() {
        let json = r#"{
            "thread": {
                "id": "t1",
                "kind": "direct",
                "status": "open",
                "from": "alice@acme",
                "from_user_id": "u1",
                "audience": "bob@acme",
                "org_id": "o1",
                "participant_count": 2,
                "reply_count": 0,
                "created_at": "2026-01-01T00:00:00Z",
                "updated_at": "2026-01-01T00:00:00Z"
            },
            "messages": []
        }"#;
        let detail: ThreadDetail = serde_json::from_str(json).unwrap();
        assert_eq!(detail.thread.id, "t1");
        assert!(detail.messages.is_empty());
    }

    #[tokio::test]
    async fn unauthorized_retries_once_after_refresh() {
        use wiremock::matchers::{bearer_token, method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let server = MockServer::start().await;

        Mock::given(method("GET"))
            .and(path("/v1/auth/me"))
            .and(bearer_token("stale-jwt"))
            .respond_with(ResponseTemplate::new(401).set_body_string("expired"))
            .expect(1)
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/v1/auth/token"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "access_token": "fresh-jwt"
            })))
            .expect(1)
            .mount(&server)
            .await;

        Mock::given(method("GET"))
            .and(path("/v1/auth/me"))
            .and(bearer_token("fresh-jwt"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "user": {
                    "id": "u1",
                    "handle": "alice@acme",
                    "org_id": "o1",
                    "pubkey": "[0]",
                    "created_at": "2026-01-01T00:00:00Z"
                }
            })))
            .expect(1)
            .mount(&server)
            .await;

        let client = HubClient::new(
            HubConfig::new(server.uri(), "stale-jwt")
                .with_refresh_token(Some("refresh-jwt".into())),
        )
        .unwrap();
        let user = client.me().await.unwrap();
        assert_eq!(user.handle, "alice@acme");
        assert_eq!(client.access_token(), "fresh-jwt");
    }

    #[tokio::test]
    async fn primary_draft_picks_max_updated_at() {
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let env = sample_envelope();
        let server = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/v1/drafts"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "drafts": [
                    {
                        "id": "old",
                        "user_id": "u1",
                        "org_id": "o1",
                        "envelope": env,
                        "created_at": "2026-01-01T00:00:00Z",
                        "updated_at": "2026-01-01T00:00:00Z"
                    },
                    {
                        "id": "new",
                        "user_id": "u1",
                        "org_id": "o1",
                        "envelope": env,
                        "created_at": "2026-01-02T00:00:00Z",
                        "updated_at": "2026-01-03T00:00:00Z"
                    },
                    {
                        "id": "mid",
                        "user_id": "u1",
                        "org_id": "o1",
                        "envelope": env,
                        "created_at": "2026-01-02T12:00:00Z",
                        "updated_at": "2026-01-02T00:00:00Z"
                    }
                ]
            })))
            .expect(1)
            .mount(&server)
            .await;

        let client = HubClient::new(HubConfig::new(server.uri(), "tok")).unwrap();
        let draft = client.primary_draft().await.unwrap().unwrap();
        assert_eq!(draft.id, "new");
    }

    #[tokio::test]
    #[ignore = "requires running hub; set MUTANDE_HUB_URL and MUTANDE_JWT"]
    async fn live_me() {
        let cfg = HubConfig::new(
            std::env::var("MUTANDE_HUB_URL").unwrap_or_else(|_| "http://localhost:8000".into()),
            std::env::var("MUTANDE_JWT").expect("MUTANDE_JWT"),
        );
        let client = HubClient::new(cfg).unwrap();
        let user = client.me().await.unwrap();
        assert!(!user.handle.is_empty());
    }

    /// Real `seal` → hub accepts createThread JSON → `get_thread` → `open` plaintext.
    #[tokio::test]
    async fn seal_hub_create_get_open_roundtrip() {
        use crate::crypto::{device_public_from_secret, open, seal, DeviceSecretKey};
        use crypto_box::aead::OsRng;
        use crypto_box::SecretKey;
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let sk = SecretKey::generate(&mut OsRng);
        let secret = DeviceSecretKey(sk.to_bytes());
        let pk = device_public_from_secret(&secret);
        let plaintext = b"e2e seal via hub wire shapes";
        let envelope = seal(plaintext, &[pk]).unwrap();

        let server = MockServer::start().await;
        let thread_id = "thread-e2e-1";
        let message_id = "msg-e2e-1";
        let thread_meta = serde_json::json!({
            "id": thread_id,
            "kind": "direct",
            "status": "open",
            "from": "alice@acme",
            "from_user_id": "u1",
            "audience": "bob@acme",
            "org_id": "o1",
            "participant_count": 2,
            "reply_count": 0,
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z"
        });

        Mock::given(method("POST"))
            .and(path("/v1/threads"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "thread": thread_meta,
                "message_id": message_id
            })))
            .expect(1)
            .mount(&server)
            .await;

        let client = HubClient::new(HubConfig::new(server.uri(), "test-jwt")).unwrap();
        let created = client.create_thread("bob@acme", &envelope).await.unwrap();
        assert_eq!(created.thread.id, thread_id);

        let requests = server.received_requests().await.unwrap();
        let post = requests
            .iter()
            .find(|r| r.method.as_str() == "POST")
            .expect("createThread POST");
        let body: serde_json::Value = serde_json::from_slice(&post.body).unwrap();
        assert_eq!(body["to"], "bob@acme");
        let posted: Envelope = serde_json::from_value(body["envelope"].clone()).unwrap();
        assert_eq!(posted, envelope);
        assert_eq!(posted.version, 1);
        assert!(posted.ciphertext.len() > plaintext.len());
        assert!(!posted.wraps.is_empty());

        let detail = ThreadDetail {
            thread: created.thread.clone(),
            messages: vec![ThreadMessage {
                id: message_id.into(),
                thread_id: thread_id.into(),
                from_user_id: "u1".into(),
                from_handle: "alice@acme".into(),
                envelope: posted,
                created_at: "2026-01-01T00:00:00Z".into(),
                sender_only: None,
            }],
        };

        Mock::given(method("GET"))
            .and(path(format!("/v1/threads/{thread_id}")))
            .respond_with(ResponseTemplate::new(200).set_body_json(&detail))
            .expect(1)
            .mount(&server)
            .await;

        let fetched = client.get_thread(thread_id).await.unwrap();
        assert_eq!(fetched.messages.len(), 1);
        let opened = open(&fetched.messages[0].envelope, &secret).unwrap();
        assert_eq!(opened, plaintext);
    }
}
