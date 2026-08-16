//! HTTPS client for Mutande hub (ciphertext in/out only).
//! Auth: Auth0 access token as Bearer; refresh via Auth0 `/oauth/token`.

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
    pub auth0_domain: Option<String>,
    pub auth0_client_id: Option<String>,
    /// Invoked with (access_token, optional new refresh_token) after refresh.
    #[allow(clippy::type_complexity)]
    pub on_tokens: Option<Arc<dyn Fn(String, Option<String>) + Send + Sync>>,
}

impl std::fmt::Debug for HubConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HubConfig")
            .field("hub_url", &self.hub_url)
            .field("token", &"***")
            .field("refresh_token", &self.refresh_token.as_ref().map(|_| "***"))
            .field("auth0_domain", &self.auth0_domain)
            .field("auth0_client_id", &self.auth0_client_id.as_ref().map(|_| "***"))
            .field("on_tokens", &self.on_tokens.is_some())
            .finish()
    }
}

impl HubConfig {
    pub fn new(hub_url: impl Into<String>, token: impl Into<String>) -> Self {
        Self {
            hub_url: hub_url.into().trim_end_matches('/').to_string(),
            token: token.into(),
            refresh_token: None,
            auth0_domain: None,
            auth0_client_id: None,
            on_tokens: None,
        }
    }

    pub fn with_refresh_token(mut self, refresh_token: Option<String>) -> Self {
        self.refresh_token = refresh_token;
        self
    }

    pub fn with_auth0(
        mut self,
        domain: Option<String>,
        client_id: Option<String>,
    ) -> Self {
        self.auth0_domain = domain;
        self.auth0_client_id = client_id;
        self
    }

    pub fn with_on_tokens(
        mut self,
        cb: impl Fn(String, Option<String>) + Send + Sync + 'static,
    ) -> Self {
        self.on_tokens = Some(Arc::new(cb));
        self
    }
}

#[derive(Clone)]
pub struct HubClient {
    client: Client,
    hub_url: String,
    token: Arc<Mutex<String>>,
    refresh_token: Arc<Mutex<Option<String>>>,
    auth0_domain: Option<String>,
    auth0_client_id: Option<String>,
    on_tokens: Option<Arc<dyn Fn(String, Option<String>) + Send + Sync>>,
}

impl HubClient {
    pub fn new(config: HubConfig) -> Result<Self> {
        let client = Client::builder()
            .user_agent("mutande-core/0.1")
            // Bound hub RTT so local RPCs (e.g. get_status → /me) cannot hang
            // past the Flutter client's status timeout.
            .timeout(std::time::Duration::from_secs(10))
            .build()
            .context("build HTTP client")?;
        Ok(Self {
            client,
            hub_url: config.hub_url,
            token: Arc::new(Mutex::new(config.token)),
            refresh_token: Arc::new(Mutex::new(config.refresh_token)),
            auth0_domain: config.auth0_domain,
            auth0_client_id: config.auth0_client_id,
            on_tokens: config.on_tokens,
        })
    }

    pub fn hub_url(&self) -> &str {
        &self.hub_url
    }

    pub fn access_token(&self) -> String {
        self.token.lock().unwrap().clone()
    }

    fn set_tokens(&self, access_token: String, refresh_token: Option<String>) {
        *self.token.lock().unwrap() = access_token.clone();
        if let Some(rt) = &refresh_token {
            *self.refresh_token.lock().unwrap() = Some(rt.clone());
        }
        if let Some(cb) = &self.on_tokens {
            cb(access_token, refresh_token);
        }
    }

    /// Exchange Auth0 refresh token for a new access token.
    pub async fn refresh_auth0_token(&self) -> Result<Auth0TokenResponse> {
        let domain = self
            .auth0_domain
            .as_deref()
            .context("Auth0 domain required for token refresh")?;
        let client_id = self
            .auth0_client_id
            .as_deref()
            .context("Auth0 client_id required for token refresh")?;
        let refresh = self
            .refresh_token
            .lock()
            .unwrap()
            .clone()
            .context("no Auth0 refresh token")?;
        self.exchange_auth0_refresh(domain, client_id, &refresh)
            .await
    }

    async fn exchange_auth0_refresh(
        &self,
        domain: &str,
        client_id: &str,
        refresh_token: &str,
    ) -> Result<Auth0TokenResponse> {
        let url = auth0_token_endpoint(domain);
        let body = serde_json::json!({
            "grant_type": "refresh_token",
            "client_id": client_id,
            "refresh_token": refresh_token,
        });
        let resp = self
            .client
            .post(&url)
            .json(&body)
            .send()
            .await
            .context("Auth0 refresh token")?;
        if resp.status().is_success() {
            resp.json()
                .await
                .context("decode Auth0 token response")
        } else {
            Err(hub_error(
                resp.status(),
                resp.text().await.unwrap_or_default(),
            ))
        }
    }

    /// On 401 with Auth0 refresh credentials: refresh once, update tokens, return true.
    async fn try_refresh_after_unauthorized(&self) -> bool {
        match self.refresh_auth0_token().await {
            Ok(tok) => {
                self.set_tokens(tok.access_token, tok.refresh_token);
                true
            }
            Err(err) => {
                tracing::warn!(error = %err, "Auth0 token refresh failed");
                false
            }
        }
    }

    /// `GET /v1/me` (Auth0 session + onboarding state).
    pub async fn me(&self) -> Result<MeResponse> {
        self.get_json("/v1/me").await
    }

    /// Compat alias used by older call sites / docs.
    pub async fn auth_me(&self) -> Result<MeResponse> {
        self.get_json("/v1/auth/me").await
    }

    pub async fn create_org(
        &self,
        slug: &str,
        name: Option<&str>,
        handle: Option<&str>,
    ) -> Result<MeResponse> {
        let body = CreateOrgRequest {
            slug: slug.to_string(),
            name: name.map(str::to_string),
            handle: handle.map(str::to_string),
        };
        self.post_json("/v1/orgs", &body, true).await
    }

    pub async fn join_org(
        &self,
        invite_code: &str,
        handle: Option<&str>,
    ) -> Result<MeResponse> {
        let body = JoinOrgRequest {
            invite_code: invite_code.to_string(),
            handle: handle.map(str::to_string),
        };
        self.post_json("/v1/onboarding/join", &body, true).await
    }

    pub async fn register_device(
        &self,
        pubkey: &DevicePubKey,
        platform: &str,
        agent_slug: Option<&str>,
    ) -> Result<Device> {
        let body = RegisterDeviceRequest {
            pubkey: pubkey_to_hub_string(pubkey),
            platform: platform.to_string(),
            agent_slug: agent_slug.map(str::to_string),
        };
        let resp: RegisterDeviceResponse = self.post_json("/v1/devices", &body, true).await?;
        Ok(resp.device)
    }

    pub async fn list_devices(&self) -> Result<Vec<Device>> {
        let resp: ListDevicesResponse = self.get_json("/v1/devices").await?;
        Ok(resp.devices)
    }

    /// Sidecar capability handshake. Canonical path is `/connect/sidecar`;
    /// hub `/register` remains a compat alias that maps to the same store helper.
    pub async fn register_agent(&self, slug: &str) -> Result<Agent> {
        self.connect_sidecar(slug).await
    }

    pub async fn connect_sidecar(&self, slug: &str) -> Result<Agent> {
        let body = RegisterAgentRequest {
            slug: slug.to_string(),
        };
        let resp: RegisterAgentResponse = self
            .post_json("/v1/agents/connect/sidecar", &body, true)
            .await?;
        Ok(resp.agent)
    }

    pub async fn list_agents(&self) -> Result<AgentListResponse> {
        self.get_json("/v1/agents").await
    }

    pub async fn get_transport_defaults(&self) -> Result<AgentTransportPrefs> {
        self.get_json("/v1/agents/transport-defaults").await
    }

    pub async fn set_transport_default(
        &self,
        slug: &str,
        transport: &str,
    ) -> Result<AgentTransportPrefs> {
        let body = SetTransportDefaultRequest {
            slug: slug.to_string(),
            transport: transport.to_string(),
        };
        self.put_json("/v1/agents/transport-defaults", &body).await
    }

    pub async fn list_agents_for_handle(&self, handle: &str) -> Result<AgentsForHandleResponse> {
        let encoded = handle.replace('@', "%40").replace('/', "%2F");
        self.get_json(&format!("/v1/agents?handle={encoded}")).await
    }

    pub async fn set_default_agent(&self, agent_id: &str) -> Result<Agent> {
        let body = SetDefaultAgentRequest {
            agent_id: agent_id.to_string(),
        };
        let resp: SetDefaultAgentResponse = self.put_json("/v1/agents/default", &body).await?;
        Ok(resp.agent)
    }

    pub async fn rename_agent(&self, agent_id: &str, slug: &str) -> Result<Agent> {
        let body = RenameAgentRequest {
            slug: slug.to_string(),
        };
        let resp: RenameAgentResponse = self
            .patch_json(&format!("/v1/agents/{agent_id}"), &body)
            .await?;
        Ok(resp.agent)
    }

    pub async fn get_router(&self) -> Result<RouterConfig> {
        self.get_json("/v1/agents/router").await
    }

    pub async fn set_router(
        &self,
        default_agent_id: Option<&str>,
        rules: Option<Vec<RoutingRule>>,
    ) -> Result<RouterConfig> {
        let body = SetRouterRequest {
            default_agent_id: default_agent_id.map(str::to_string),
            rules,
        };
        self.put_json("/v1/agents/router", &body).await
    }

    pub async fn list_contacts(&self) -> Result<Vec<Contact>> {
        let resp: ContactsResponse = self.get_json("/v1/contacts").await?;
        Ok(resp.contacts)
    }

    pub async fn list_external_contacts(&self) -> Result<Vec<Contact>> {
        let resp: ContactsResponse = self.get_json("/v1/contacts/external").await?;
        Ok(resp.contacts)
    }

    /// Public enterprise listing + warn banner (§7.2).
    pub async fn get_registry_listing(
        &self,
        id_or_address: &str,
    ) -> Result<RegistryListingPublic> {
        let encoded = encode_path_segment(id_or_address.trim());
        self.get_json(&format!("/v1/registry/listing/{encoded}"))
            .await
    }

    pub async fn issue_pairing_pin(&self) -> Result<PairingPin> {
        self.post_json("/v1/contacts/pairing/pin", &serde_json::json!({}), true)
            .await
    }

    pub async fn get_pairing_pin(&self) -> Result<Option<PairingPin>> {
        let resp: PairingPinGetResponse = self.get_json("/v1/contacts/pairing/pin").await?;
        Ok(resp.pin)
    }

    pub async fn rotate_pairing_pin(&self) -> Result<PairingPin> {
        self.post_json(
            "/v1/contacts/pairing/pin/rotate",
            &serde_json::json!({}),
            true,
        )
        .await
    }

    pub async fn submit_pair_request(
        &self,
        handle: &str,
        pin: &str,
        intro: Option<&str>,
    ) -> Result<PairRequest> {
        let body = SubmitPairRequest {
            handle: handle.to_string(),
            pin: pin.to_string(),
            intro: intro.map(str::to_string),
        };
        let resp: PairRequestResponse = self
            .post_json("/v1/contacts/pairing/request", &body, true)
            .await?;
        Ok(resp.request)
    }

    pub async fn list_pending_pair_requests(&self) -> Result<PendingPairRequests> {
        self.get_json("/v1/contacts/pairing/pending").await
    }

    pub async fn approve_pair_request(&self, request_id: &str) -> Result<ApprovePairResponse> {
        self.post_json(
            &format!("/v1/contacts/pairing/{request_id}/approve"),
            &serde_json::json!({}),
            true,
        )
        .await
    }

    pub async fn deny_pair_request(&self, request_id: &str) -> Result<()> {
        let _: serde_json::Value = self
            .post_json(
                &format!("/v1/contacts/pairing/{request_id}/deny"),
                &serde_json::json!({}),
                true,
            )
            .await?;
        Ok(())
    }

    pub async fn propose_thread_downgrade(
        &self,
        thread_id: &str,
        agent_slug: &str,
        from_agent: Option<&str>,
    ) -> Result<ProposeDowngradeResponse> {
        let mut body = serde_json::json!({ "agent_slug": agent_slug });
        if let Some(fa) = from_agent.map(str::trim).filter(|s| !s.is_empty()) {
            body["from_agent"] = serde_json::json!(fa);
        }
        self.post_json(
            &format!("/v1/threads/{thread_id}/downgrade-proposals"),
            &body,
            true,
        )
        .await
    }

    pub async fn list_pending_thread_downgrades(&self) -> Result<PendingDowngradeProposals> {
        self.get_json("/v1/threads/downgrade-proposals/pending")
            .await
    }

    pub async fn approve_thread_downgrade(
        &self,
        thread_id: &str,
        proposal_id: &str,
    ) -> Result<ApproveDowngradeResponse> {
        self.post_json(
            &format!("/v1/threads/{thread_id}/downgrade-proposals/{proposal_id}/approve"),
            &serde_json::json!({}),
            true,
        )
        .await
    }

    pub async fn deny_thread_downgrade(
        &self,
        thread_id: &str,
        proposal_id: &str,
    ) -> Result<ThreadDowngradeProposal> {
        let resp: serde_json::Value = self
            .post_json(
                &format!("/v1/threads/{thread_id}/downgrade-proposals/{proposal_id}/deny"),
                &serde_json::json!({}),
                true,
            )
            .await?;
        serde_json::from_value(resp.get("proposal").cloned().unwrap_or(resp))
            .context("parse deny downgrade response")
    }

    pub async fn unpair_external_contact(&self, link_id: &str) -> Result<UnpairResponse> {
        let path = format!("/v1/contacts/external/{link_id}");
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
            if resp.status().is_success() {
                return resp
                    .json()
                    .await
                    .with_context(|| format!("decode DELETE {path}"));
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

    pub async fn submit_feedback(
        &self,
        message: &str,
        category: Option<&str>,
        app_version: Option<&str>,
        platform: Option<&str>,
    ) -> Result<Feedback> {
        let body = SubmitFeedbackRequest {
            message: message.to_string(),
            category: category.map(str::to_string),
            app_version: app_version.map(str::to_string),
            platform: platform.map(str::to_string),
        };
        let resp: SubmitFeedbackResponse = self.post_json("/v1/feedback", &body, true).await?;
        Ok(resp.feedback)
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

    pub async fn create_thread(
        &self,
        to: &str,
        envelope: &Envelope,
        from_agent: Option<&str>,
        turns: Option<&[HubAwaitingEntry]>,
    ) -> Result<CreateThreadResponse> {
        let body = CreateThreadRequest {
            to,
            envelope: Some(envelope),
            app_envelope: None,
            from_agent,
            turns,
            collab_id: None,
            lane_id: None,
            assigned_to: None,
            tags: None,
            due_on: None,
            checklist: None,
        };
        self.post_json("/v1/threads", &body, true).await
    }

    /// Non-E2E create — posts hub-readable `app_envelope` (web / external / enterprise).
    pub async fn create_thread_app_envelope(
        &self,
        to: &str,
        app_envelope: &AppEnvelopePayload,
        from_agent: Option<&str>,
        turns: Option<&[HubAwaitingEntry]>,
    ) -> Result<CreateThreadResponse> {
        let body = CreateThreadRequest {
            to,
            envelope: None,
            app_envelope: Some(app_envelope),
            from_agent,
            turns,
            collab_id: None,
            lane_id: None,
            assigned_to: None,
            tags: None,
            due_on: None,
            checklist: None,
        };
        self.post_json("/v1/threads", &body, true).await
    }

    pub async fn get_thread(&self, thread_id: &str) -> Result<ThreadDetail> {
        self.get_json(&format!("/v1/threads/{thread_id}")).await
    }

    pub async fn reply_to_thread(
        &self,
        thread_id: &str,
        envelope: &Envelope,
        from_agent: Option<&str>,
        to_agent: Option<&str>,
        parent_message_id: Option<&str>,
        turns: Option<&[HubAwaitingEntry]>,
    ) -> Result<()> {
        let body = ReplyRequest {
            envelope: Some(envelope),
            app_envelope: None,
            from_agent,
            to_agent,
            parent_message_id,
            turns,
        };
        let _: serde_json::Value = self
            .post_json(
                &format!("/v1/threads/{thread_id}/replies"),
                &body,
                true,
            )
            .await?;
        Ok(())
    }

    pub async fn reply_to_thread_app_envelope(
        &self,
        thread_id: &str,
        app_envelope: &AppEnvelopePayload,
        from_agent: Option<&str>,
        to_agent: Option<&str>,
        parent_message_id: Option<&str>,
        turns: Option<&[HubAwaitingEntry]>,
    ) -> Result<()> {
        let body = ReplyRequest {
            envelope: None,
            app_envelope: Some(app_envelope),
            from_agent,
            to_agent,
            parent_message_id,
            turns,
        };
        let _: serde_json::Value = self
            .post_json(
                &format!("/v1/threads/{thread_id}/replies"),
                &body,
                true,
            )
            .await?;
        Ok(())
    }

    pub async fn toggle_message_upvote(
        &self,
        thread_id: &str,
        message_id: &str,
        from_agent: Option<&str>,
    ) -> Result<ToggleUpvoteResponse> {
        let body = ToggleUpvoteRequest { from_agent };
        self.post_json(
            &format!("/v1/threads/{thread_id}/messages/{message_id}/upvote"),
            &body,
            true,
        )
        .await
    }

    pub async fn post_message_receipt(
        &self,
        thread_id: &str,
        message_id: &str,
        from_agent: Option<&str>,
    ) -> Result<PostReceiptResponse> {
        let body = PostReceiptRequest { from_agent };
        self.post_json(
            &format!("/v1/threads/{thread_id}/messages/{message_id}/receipt"),
            &body,
            true,
        )
        .await
    }

    pub async fn create_thread_collab(
        &self,
        to: &str,
        envelope: Option<&Envelope>,
        app_envelope: Option<&AppEnvelopePayload>,
        from_agent: Option<&str>,
        turns: Option<&[HubAwaitingEntry]>,
        collab_id: &str,
        lane_id: Option<&str>,
        assigned_to: Option<&str>,
        tags: Option<&[String]>,
        due_on: Option<&str>,
        checklist: Option<&[CollabChecklistItem]>,
    ) -> Result<CreateThreadResponse> {
        let body = CreateThreadRequest {
            to,
            envelope,
            app_envelope,
            from_agent,
            turns,
            collab_id: Some(collab_id),
            lane_id,
            assigned_to,
            tags,
            due_on,
            checklist,
        };
        self.post_json("/v1/threads", &body, true).await
    }

    pub async fn list_collabs(&self) -> Result<ListCollabsResponse> {
        self.get_json("/v1/collabs").await
    }

    pub async fn get_collab(&self, collab_id: &str) -> Result<Collab> {
        let resp: CollabResponse = self
            .get_json(&format!("/v1/collabs/{collab_id}"))
            .await?;
        Ok(resp.collab)
    }

    pub async fn create_collab(
        &self,
        name: &str,
        steerer_handles: &[String],
        roster_addresses: &[String],
        instructions: Option<&str>,
        artifacts: &[CollabArtifactSummary],
    ) -> Result<Collab> {
        let steerer_ref = if steerer_handles.is_empty() {
            None
        } else {
            Some(steerer_handles)
        };
        let roster_ref = if roster_addresses.is_empty() {
            None
        } else {
            Some(roster_addresses)
        };
        let artifacts_ref = if artifacts.is_empty() {
            None
        } else {
            Some(artifacts)
        };
        let body = CreateCollabRequest {
            name,
            steerer_handles: steerer_ref,
            roster_addresses: roster_ref,
            instructions,
            artifacts: artifacts_ref,
        };
        let resp: CollabResponse = self.post_json("/v1/collabs", &body, true).await?;
        Ok(resp.collab)
    }

    pub async fn set_lane(
        &self,
        collab_id: &str,
        thread_id: &str,
        lane_id: &str,
        before_thread_id: Option<&str>,
        after_thread_id: Option<&str>,
    ) -> Result<ThreadMeta> {
        let body = SetLaneRequest {
            thread_id,
            lane_id,
            before_thread_id,
            after_thread_id,
        };
        let resp: serde_json::Value = self
            .post_json(&format!("/v1/collabs/{collab_id}/lane"), &body, true)
            .await?;
        if let Some(thread) = resp.get("thread") {
            Ok(serde_json::from_value(thread.clone())?)
        } else {
            serde_json::from_value(resp).context("set_lane response")
        }
    }

    pub async fn add_learning(
        &self,
        collab_id: &str,
        notes: Option<&str>,
        from_agent: Option<&str>,
        envelope: Option<&Envelope>,
    ) -> Result<serde_json::Value> {
        let body = AddLearningRequest {
            notes,
            from_agent,
            from_agent_id: None,
            envelope,
        };
        self.post_json(&format!("/v1/collabs/{collab_id}/learnings"), &body, true)
            .await
    }

    pub async fn update_collab_instructions(
        &self,
        collab_id: &str,
        instructions: Option<&str>,
    ) -> Result<Collab> {
        let body = UpdateInstructionsRequest { instructions };
        let resp: CollabResponse = self
            .post_json(
                &format!("/v1/collabs/{collab_id}/instructions"),
                &body,
                true,
            )
            .await?;
        Ok(resp.collab)
    }

    pub async fn add_collab_artifacts(
        &self,
        collab_id: &str,
        artifacts: &[CollabArtifactSummary],
    ) -> Result<Collab> {
        let body = AddCollabArtifactsRequest { artifacts };
        let resp: CollabResponse = self
            .post_json(
                &format!("/v1/collabs/{collab_id}/artifacts"),
                &body,
                true,
            )
            .await?;
        Ok(resp.collab)
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

    pub async fn delete_thread(&self, thread_id: &str) -> Result<()> {
        let path = format!("/v1/threads/{thread_id}");
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

            // Hub returns 200 for inbox dismiss / sender purge / orphan cleanup.
            // Do not treat 404 as success — that masks org-mismatch / real misses.
            if resp.status().is_success() {
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

    /// PUT ciphertext bytes to a hub-issued presigned (or mock) upload URL.
    pub async fn put_presigned(&self, upload_url: &str, body: &[u8]) -> Result<()> {
        let resp = self
            .client
            .put(upload_url)
            .header(reqwest::header::CONTENT_TYPE, "application/octet-stream")
            .body(body.to_vec())
            .send()
            .await
            .context("PUT presigned blob")?;
        if resp.status().is_success() {
            Ok(())
        } else {
            Err(hub_error(
                resp.status(),
                resp.text().await.unwrap_or_default(),
            ))
        }
    }

    /// GET ciphertext bytes from a hub-issued presigned (or mock) download URL.
    pub async fn get_presigned(&self, download_url: &str) -> Result<Vec<u8>> {
        let resp = self
            .client
            .get(download_url)
            .send()
            .await
            .context("GET presigned blob")?;
        if resp.status().is_success() {
            resp.bytes()
                .await
                .map(|b| b.to_vec())
                .context("read presigned blob body")
        } else {
            Err(hub_error(
                resp.status(),
                resp.text().await.unwrap_or_default(),
            ))
        }
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

    async fn patch_json<T, B>(&self, path: &str, body: &B) -> Result<T>
    where
        T: DeserializeOwned,
        B: Serialize + ?Sized,
    {
        let mut attempted_refresh = false;
        loop {
            let token = self.access_token();
            let resp = self
                .client
                .patch(self.url(path))
                .json(body)
                .bearer_auth(&token)
                .send()
                .await
                .with_context(|| format!("PATCH {path}"))?;

            if resp.status().is_success() {
                return resp
                    .json()
                    .await
                    .with_context(|| format!("decode PATCH {path}"));
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

/// Percent-encode a single URL path segment (enterprise addresses contain `@`).
fn encode_path_segment(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 3);
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char);
            }
            _ => {
                out.push('%');
                out.push_str(&format!("{b:02X}"));
            }
        }
    }
    out
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

/// Auth0 token endpoint. Plain host → `https://{host}/oauth/token`.
/// Full `http(s)://…` URL (tests / custom) → `{base}/oauth/token`.
pub fn auth0_token_endpoint(domain: &str) -> String {
    let d = domain.trim().trim_end_matches('/');
    if d.starts_with("http://") || d.starts_with("https://") {
        format!("{d}/oauth/token")
    } else {
        format!("https://{d}/oauth/token")
    }
}

/// Auth0 authorize endpoint (same host rules as [`auth0_token_endpoint`]).
pub fn auth0_authorize_endpoint(domain: &str) -> String {
    let d = domain.trim().trim_end_matches('/');
    if d.starts_with("http://") || d.starts_with("https://") {
        format!("{d}/authorize")
    } else {
        format!("https://{d}/authorize")
    }
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
    fn create_org_request_shape() {
        let req = CreateOrgRequest {
            slug: "acme".into(),
            name: Some("Acme Inc".into()),
            handle: Some("alice".into()),
        };
        let json = serde_json::to_value(&req).unwrap();
        assert_eq!(json["slug"], "acme");
        assert_eq!(json["name"], "Acme Inc");
        assert_eq!(json["handle"], "alice");
    }

    #[test]
    fn me_response_onboarded_helpers() {
        let needs = MeResponse {
            auth0_sub: "auth0|1".into(),
            email: None,
            needs_onboarding: true,
            onboarded: Some(false),
            user: None,
            org: None,
        };
        assert!(!needs.is_onboarded());

        let ready = MeResponse {
            auth0_sub: "auth0|1".into(),
            email: Some("a@x.com".into()),
            needs_onboarding: false,
            onboarded: Some(true),
            user: Some(User {
                id: "u1".into(),
                auth0_sub: Some("auth0|1".into()),
                email: None,
                handle: Some("alice@acme".into()),
                org_id: Some("o1".into()),
                role: Some("org_admin".into()),
                pubkey: None,
                created_at: "2026-01-01T00:00:00Z".into(),
            }),
            org: None,
        };
        assert!(ready.is_onboarded());
    }

    #[test]
    fn create_thread_request_uses_to_not_recipient() {
        let env = sample_envelope();
        let req = CreateThreadRequest {
            to: "bob@acme",
            envelope: Some(&env),
            app_envelope: None,
            from_agent: None,
            turns: None,
            collab_id: None,
            lane_id: None,
            assigned_to: None,
            tags: None,
            due_on: None,
            checklist: None,
        };
        let json = serde_json::to_value(&req).unwrap();
        assert_eq!(json["to"], "bob@acme");
        assert!(json.get("recipient").is_none());
        assert!(json.get("collab_id").is_none());
        assert_eq!(json["envelope"]["version"], 1);
        assert!(json["envelope"]["content_nonce"].is_array());
    }

    #[test]
    fn reply_request_wraps_envelope_object() {
        let env = sample_envelope();
        let req = ReplyRequest {
            envelope: Some(&env),
            app_envelope: None,
            from_agent: None,
            to_agent: None,
            parent_message_id: None,
            turns: None,
        };
        let json = serde_json::to_value(&req).unwrap();
        assert!(json["envelope"]["wraps"].is_array());
    }

    #[test]
    fn contacts_response_deserializes_handle_and_pubkey() {
        let json = r#"{"contacts":[
            {"handle":"@all@acme","pubkey":null,"devices":[]},
            {"handle":"bob@acme","pubkey":"[1,2,3]","devices":[{"pubkey":"[1,2,3]","platform":"macos"}]}
        ]}"#;
        let resp: ContactsResponse = serde_json::from_str(json).unwrap();
        assert_eq!(resp.contacts.len(), 2);
        assert_eq!(resp.contacts[0].handle, "@all@acme");
        assert!(resp.contacts[0].pubkey.is_none());
        assert_eq!(resp.contacts[1].handle, "bob@acme");
        assert_eq!(resp.contacts[1].pubkey.as_deref(), Some("[1,2,3]"));
        assert_eq!(resp.contacts[1].devices.len(), 1);
    }

    #[test]
    fn collab_view_deserializes_hub_card_summaries() {
        let json = r#"{
            "id": "c1",
            "org_id": "o1",
            "name": "Launch",
            "created_by": "u1",
            "created_at": "2026-08-15T00:00:00Z",
            "updated_at": "2026-08-15T00:00:00Z",
            "encryption_mode": "e2e",
            "lists": [{"id": "backlog", "name": "Backlog", "position": 0}],
            "roster": [],
            "memory_thread_id": "m1",
            "card_count": 1,
            "steerers": [{"user_id": "u1", "handle": "alice@acme"}],
            "cards": [{
                "id": "t1",
                "lane_id": "backlog",
                "lane_position": 1000,
                "status": "open",
                "from": "alice@acme",
                "audience": "bob@acme",
                "updated_at": "2026-08-15T00:00:00Z",
                "your_status": "pending"
            }],
            "learnings": [{
                "id": "l1",
                "created_at": "2026-08-15T00:00:00Z",
                "from_handle": "alice@acme",
                "notes": "ship friday"
            }]
        }"#;
        let collab: Collab = serde_json::from_str(json).unwrap();
        assert_eq!(collab.cards.len(), 1);
        assert_eq!(collab.cards[0].id, "t1");
        assert_eq!(collab.cards[0].lane_id.as_deref(), Some("backlog"));
        assert_eq!(collab.learnings.len(), 1);
        assert_eq!(collab.learnings[0].created_at, "2026-08-15T00:00:00Z");
        assert_eq!(collab.learnings[0].from_handle.as_deref(), Some("alice@acme"));
    }

    #[test]
    fn list_collabs_response_deserializes_portfolio() {
        let json = r#"{
            "collabs": [{
                "id": "c1",
                "org_id": "o1",
                "name": "Launch",
                "created_by": "u1",
                "created_at": "2026-08-15T00:00:00Z",
                "updated_at": "2026-08-15T00:00:00Z",
                "encryption_mode": "e2e",
                "card_count": 2,
                "open": 1,
                "backlog": 0,
                "doing": 1,
                "done": 0,
                "needs_you": 1
            }],
            "portfolio": {
                "activity": [{"date": "2026-08-15", "count": 2}],
                "lane_totals": {"backlog": 0, "doing": 1, "done": 0},
                "totals": {"collabs": 1, "open": 1, "doing": 1, "needs_you": 1}
            }
        }"#;
        let resp: ListCollabsResponse = serde_json::from_str(json).unwrap();
        assert_eq!(resp.collabs.len(), 1);
        assert_eq!(resp.collabs[0].open, 1);
        assert_eq!(resp.collabs[0].doing, 1);
        assert_eq!(resp.collabs[0].backlog, 0);
        assert_eq!(resp.collabs[0].done, 0);
        assert_eq!(resp.portfolio.totals.needs_you, 1);
        assert_eq!(resp.portfolio.activity[0].date, "2026-08-15");
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
    async fn unauthorized_retries_once_after_auth0_refresh() {
        use wiremock::matchers::{bearer_token, method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let auth0 = MockServer::start().await;
        let hub = MockServer::start().await;

        Mock::given(method("GET"))
            .and(path("/v1/me"))
            .and(bearer_token("stale-at"))
            .respond_with(ResponseTemplate::new(401).set_body_string("expired"))
            .expect(1)
            .mount(&hub)
            .await;

        Mock::given(method("POST"))
            .and(path("/oauth/token"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "access_token": "fresh-at",
                "refresh_token": "fresh-rt"
            })))
            .expect(1)
            .mount(&auth0)
            .await;

        Mock::given(method("GET"))
            .and(path("/v1/me"))
            .and(bearer_token("fresh-at"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "auth0_sub": "auth0|1",
                "needs_onboarding": false,
                "onboarded": true,
                "user": {
                    "id": "u1",
                    "handle": "alice@acme",
                    "org_id": "o1",
                    "created_at": "2026-01-01T00:00:00Z"
                }
            })))
            .expect(1)
            .mount(&hub)
            .await;

        let client = HubClient::new(
            HubConfig::new(hub.uri(), "stale-at")
                .with_refresh_token(Some("refresh-rt".into()))
                .with_auth0(Some(auth0.uri()), Some("native-client".into())),
        )
        .unwrap();
        let me = client.me().await.unwrap();
        assert_eq!(
            me.user.as_ref().and_then(|u| u.handle.as_deref()),
            Some("alice@acme")
        );
        assert_eq!(client.access_token(), "fresh-at");
    }

    #[test]
    fn auth0_endpoints_accept_plain_host_or_base_url() {
        assert_eq!(
            auth0_token_endpoint("tenant.us.auth0.com"),
            "https://tenant.us.auth0.com/oauth/token"
        );
        assert_eq!(
            auth0_authorize_endpoint("http://127.0.0.1:9999"),
            "http://127.0.0.1:9999/authorize"
        );
    }

    #[tokio::test]
    async fn me_create_org_join_register_device_wire_shapes() {
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let server = MockServer::start().await;
        let me_json = serde_json::json!({
            "auth0_sub": "auth0|1",
            "email": "a@x.com",
            "needs_onboarding": false,
            "onboarded": true,
            "user": {
                "id": "u1",
                "auth0_sub": "auth0|1",
                "handle": "alice@acme",
                "org_id": "o1",
                "role": "org_admin",
                "created_at": "2026-01-01T00:00:00Z"
            },
            "org": {
                "id": "o1",
                "slug": "acme",
                "name": "Acme",
                "created_at": "2026-01-01T00:00:00Z"
            }
        });

        Mock::given(method("GET"))
            .and(path("/v1/me"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&me_json))
            .mount(&server)
            .await;
        Mock::given(method("POST"))
            .and(path("/v1/orgs"))
            .respond_with(ResponseTemplate::new(201).set_body_json(&me_json))
            .mount(&server)
            .await;
        Mock::given(method("POST"))
            .and(path("/v1/onboarding/join"))
            .respond_with(ResponseTemplate::new(201).set_body_json(&me_json))
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

        let client = HubClient::new(HubConfig::new(server.uri(), "at")).unwrap();
        let me = client.me().await.unwrap();
        assert!(me.is_onboarded());
        assert_eq!(me.user.as_ref().unwrap().handle.as_deref(), Some("alice@acme"));

        let created = client
            .create_org("acme", Some("Acme"), Some("alice"))
            .await
            .unwrap();
        assert!(created.is_onboarded());

        let joined = client.join_org("inv-1", Some("alice@acme")).await.unwrap();
        assert!(joined.is_onboarded());

        let device = client
            .register_device(&DevicePubKey([7u8; 32]), "macos", None)
            .await
            .unwrap();
        assert_eq!(device.platform, "macos");
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
    #[ignore = "requires running hub; set MUTANDE_HUB_URL and MUTANDE_AUTH0_ACCESS_TOKEN"]
    async fn live_me() {
        let cfg = HubConfig::new(
            std::env::var("MUTANDE_HUB_URL").unwrap_or_else(|_| "http://localhost:8000".into()),
            std::env::var("MUTANDE_AUTH0_ACCESS_TOKEN").expect("MUTANDE_AUTH0_ACCESS_TOKEN"),
        );
        let client = HubClient::new(cfg).unwrap();
        let me = client.me().await.unwrap();
        assert!(!me.auth0_sub.is_empty());
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

        let client = HubClient::new(HubConfig::new(server.uri(), "test-at")).unwrap();
        let created = client
            .create_thread("bob@acme", &envelope, None, None)
            .await
            .unwrap();
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
                from_agent_id: None,
                envelope: Some(posted),
                app_envelope: None,
                content_store: Some("e2e".into()),
                created_at: "2026-01-01T00:00:00Z".into(),
                sender_only: None,
                parent_message_id: None,
                upvotes: None,
                receipts: None,
            }],
        pending_downgrade: None,
        };

        Mock::given(method("GET"))
            .and(path(format!("/v1/threads/{thread_id}")))
            .respond_with(ResponseTemplate::new(200).set_body_json(&detail))
            .expect(1)
            .mount(&server)
            .await;

        let fetched = client.get_thread(thread_id).await.unwrap();
        assert_eq!(fetched.messages.len(), 1);
        let opened = open(
            fetched.messages[0]
                .envelope
                .as_ref()
                .expect("e2e envelope"),
            &secret,
        )
        .unwrap();
        assert_eq!(opened, plaintext);
    }

    #[tokio::test]
    async fn list_agents_forwards_l1_fields_and_transport_defaults() {
        use wiremock::matchers::{body_json, method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let server = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/v1/agents"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "agents": [
                    {
                        "id": "a-sidecar",
                        "user_id": "u1",
                        "slug": "chatgpt",
                        "created_at": "2026-01-01T00:00:00Z",
                        "transport": "sidecar",
                        "visibility": "private",
                        "trust_tier": "org",
                        "mcp_endpoint": null,
                        "capabilities_updated_at": "2026-08-11T12:00:00Z"
                    },
                    {
                        "id": "a-mcp",
                        "user_id": "u1",
                        "slug": "chatgpt",
                        "created_at": "2026-01-02T00:00:00Z",
                        "transport": "mcp",
                        "visibility": "private",
                        "trust_tier": "org",
                        "mcp_endpoint": "https://mcp.mutande.online",
                        "capabilities_updated_at": "2026-08-11T12:05:00Z"
                    }
                ],
                "default_agent_id": "a-sidecar"
            })))
            .expect(1)
            .mount(&server)
            .await;

        Mock::given(method("GET"))
            .and(path("/v1/agents/transport-defaults"))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "defaults": { "chatgpt": "mcp" }
            })))
            .expect(1)
            .mount(&server)
            .await;

        Mock::given(method("PUT"))
            .and(path("/v1/agents/transport-defaults"))
            .and(body_json(serde_json::json!({
                "slug": "chatgpt",
                "transport": "sidecar"
            })))
            .respond_with(ResponseTemplate::new(200).set_body_json(&serde_json::json!({
                "defaults": { "chatgpt": "sidecar" }
            })))
            .expect(1)
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/v1/agents/connect/sidecar"))
            .and(body_json(serde_json::json!({ "slug": "cursor" })))
            .respond_with(ResponseTemplate::new(201).set_body_json(&serde_json::json!({
                "agent": {
                    "id": "a-cursor",
                    "user_id": "u1",
                    "slug": "cursor",
                    "created_at": "2026-08-11T12:00:00Z",
                    "transport": "sidecar",
                    "visibility": "private",
                    "trust_tier": "org",
                    "mcp_endpoint": null,
                    "capabilities_updated_at": "2026-08-11T12:00:00Z"
                }
            })))
            .expect(1)
            .mount(&server)
            .await;

        let client = HubClient::new(HubConfig::new(server.uri(), "tok")).unwrap();
        let list = client.list_agents().await.unwrap();
        assert_eq!(list.agents.len(), 2);
        assert_eq!(list.agents[0].transport.as_deref(), Some("sidecar"));
        assert_eq!(list.agents[1].transport.as_deref(), Some("mcp"));
        assert_eq!(list.agents[1].trust_tier.as_deref(), Some("org"));
        assert_eq!(
            list.agents[1].capabilities_updated_at.as_deref(),
            Some("2026-08-11T12:05:00Z")
        );

        let prefs = client.get_transport_defaults().await.unwrap();
        assert_eq!(prefs.defaults.get("chatgpt").map(String::as_str), Some("mcp"));

        let updated = client
            .set_transport_default("chatgpt", "sidecar")
            .await
            .unwrap();
        assert_eq!(
            updated.defaults.get("chatgpt").map(String::as_str),
            Some("sidecar")
        );

        let agent = client.register_agent("cursor").await.unwrap();
        assert_eq!(agent.slug, "cursor");
        assert_eq!(agent.transport.as_deref(), Some("sidecar"));
    }
}
