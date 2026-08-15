//! Collab boards — daemon RPC glue (wrap cards to all steerers).

use anyhow::{Context, Result, bail};
use serde_json::Value;

use crate::crypto::DevicePubKey;
use crate::hub_client::{Collab, ListCollabsResponse};

use super::state::{DaemonState, MutandeBundle};

impl DaemonState {
    pub async fn list_collabs(&self) -> Result<ListCollabsResponse> {
        let hub = self
            .hub_client()
            .context("not signed in — call auth_login first")?;
        hub.list_collabs().await
    }

    pub async fn get_collab(&self, collab_id: &str) -> Result<Collab> {
        let hub = self
            .hub_client()
            .context("not signed in — call auth_login first")?;
        hub.get_collab(collab_id).await
    }

    pub async fn create_collab(
        &self,
        name: &str,
        steerer_handles: &[String],
        roster_addresses: &[String],
        instructions: Option<&str>,
    ) -> Result<Collab> {
        let hub = self
            .hub_client()
            .context("not signed in — call auth_login first")?;
        // Omit plaintext instructions until we know encryption_mode (XOR).
        let collab = hub
            .create_collab(name, steerer_handles, roster_addresses, None)
            .await?;
        if collab.encryption_mode == "app_envelope" {
            if let Some(text) = instructions.map(str::trim).filter(|s| !s.is_empty()) {
                return hub
                    .update_collab_instructions(&collab.id, Some(text))
                    .await;
            }
        }
        Ok(collab)
    }

    pub async fn set_lane(
        &self,
        collab_id: &str,
        thread_id: &str,
        lane_id: &str,
        before_thread_id: Option<&str>,
        after_thread_id: Option<&str>,
    ) -> Result<crate::hub_client::ThreadMeta> {
        let hub = self
            .hub_client()
            .context("not signed in — call auth_login first")?;
        hub.set_lane(
            collab_id,
            thread_id,
            lane_id,
            before_thread_id,
            after_thread_id,
        )
        .await
    }

    pub async fn add_learning(
        &self,
        collab_id: &str,
        notes: &str,
        from_agent: Option<&str>,
    ) -> Result<Value> {
        let hub = self
            .hub_client()
            .context("not signed in — call auth_login first")?;
        let collab = hub.get_collab(collab_id).await?;
        if self.agent_slug_is_mcp(from_agent).await? && collab.encryption_mode == "e2e" {
            bail!("Hosted agents cannot write the brain on an E2E collab");
        }
        if collab.encryption_mode == "e2e" {
            let bundle = MutandeBundle {
                notes: Some(notes.to_string()),
                subject: Some("learning".into()),
                ..Default::default()
            };
            let plain = serde_json::to_vec(&bundle)?;
            let keys = self.collab_steerer_pubkeys(&collab).await?;
            let env = self.seal_inline_or_blob(&plain, &keys).await?;
            hub.add_learning(collab_id, Some(notes), from_agent, Some(&env))
                .await
        } else {
            hub.add_learning(collab_id, Some(notes), from_agent, None)
                .await
        }
    }

    pub async fn update_collab_instructions(
        &self,
        collab_id: &str,
        instructions: &str,
    ) -> Result<Collab> {
        let hub = self
            .hub_client()
            .context("not signed in — call auth_login first")?;
        let collab = hub.get_collab(collab_id).await?;
        if collab.encryption_mode == "e2e" {
            bail!(
                "E2E collab instructions stay on-device — plaintext updates are only for app_envelope collabs"
            );
        }
        hub.update_collab_instructions(collab_id, Some(instructions))
            .await
    }

    /// New board card: seal once to every steerer device, then POST with collab_id.
    pub async fn create_collab_card(
        &self,
        collab_id: &str,
        subject: &str,
        notes: Option<&str>,
        lane_id: Option<&str>,
        assigned_to: Option<&str>,
        agent_slug: Option<&str>,
    ) -> Result<String> {
        let hub = self
            .hub_client()
            .context("not signed in — call auth_login first")?;
        let collab = hub.get_collab(collab_id).await?;
        let from_agent = self.from_agent_for_send(agent_slug);
        if collab.encryption_mode == "e2e" && self.agent_slug_is_mcp(from_agent.as_deref()).await? {
            bail!("Hosted agents cannot create cards on an E2E collab");
        }
        let to = collab
            .steerers
            .first()
            .map(|s| s.handle.clone())
                    .or_else(|| {
                collab
                    .roster
                    .first()
                    .map(|r| r.address.clone())
            })
            .unwrap_or(self.my_bare_handle().await?);
        let bundle = MutandeBundle {
            subject: Some(subject.to_string()),
            notes: notes.map(str::to_string),
            ..Default::default()
        };
        self.create_hub_thread(
            &hub,
            &to,
            &bundle,
            from_agent.as_deref(),
            Some(collab_id),
            lane_id,
            assigned_to,
        )
        .await
    }

    pub(super) async fn collab_steerer_pubkeys(&self, collab: &Collab) -> Result<Vec<DevicePubKey>> {
        let mut keys: Vec<DevicePubKey> = Vec::new();
        for steerer in &collab.steerers {
            match self.resolve_audience_pubkeys(&steerer.handle).await {
                Ok(got) => {
                    for pk in got {
                        if !keys.iter().any(|k| k == &pk) {
                            keys.push(pk);
                        }
                    }
                }
                Err(err) => {
                    tracing::warn!(
                        handle = %steerer.handle,
                        error = %err,
                        "collab steerer pubkey resolve failed"
                    );
                }
            }
        }
        self.append_own_device_pubkeys(&mut keys).await;
        if keys.is_empty() {
            bail!("collab has no steerer device pubkeys to wrap");
        }
        Ok(keys)
    }
}
