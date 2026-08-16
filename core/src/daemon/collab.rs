//! Collab boards — daemon RPC glue (wrap cards to all steerers).

use anyhow::{Context, Result, bail};
use serde_json::Value;

use crate::crypto::DevicePubKey;
use crate::hub_client::{Collab, CollabArtifactSummary, ListCollabsResponse};

use super::state::{bundle_for_blob_artifact, BundleResource, DaemonState, MutandeBundle};

/// Flutter/RPC draft — `path` is read by RPC; this carries bytes, never a hub path.
#[derive(Clone, Debug, Default)]
pub struct CollabArtifactDraft {
    pub kind: String,
    pub label: Option<String>,
    pub url: Option<String>,
    pub name: Option<String>,
    pub mime: Option<String>,
    pub bytes: Option<Vec<u8>>,
}

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
        let mut collab = hub.get_collab(collab_id).await?;
        self.open_hub_collab_artifacts(&mut collab).await;
        let mut artifacts = collab.artifacts;
        for card in &mut collab.cards {
            let Ok(detail) = self.fetch_and_open_thread(&card.id).await else {
                continue;
            };
            let root_subject = detail
                .messages
                .iter()
                .find(|message| message.parent_message_id.is_none())
                .and_then(|message| message.bundle.as_ref())
                .and_then(|bundle| bundle.subject.as_deref())
                .map(str::trim)
                .filter(|subject| !subject.is_empty())
                .map(str::to_string);
            if root_subject.is_some() {
                card.last_subject = root_subject;
            }
            let card_title = card
                .last_subject
                .clone()
                .or_else(|| card.audience.clone())
                .unwrap_or_else(|| "Card".into());
            for message in detail.messages {
                let Some(bundle) = message.bundle else {
                    continue;
                };
                for resource in bundle.resources {
                    if resource.name.trim().is_empty() {
                        continue;
                    }
                    artifacts.push(CollabArtifactSummary {
                        kind: "file".into(),
                        label: Some(resource.name.clone()),
                        url: None,
                        name: resource.name,
                        mime: resource.mime,
                        size: resource.size,
                        path: resource.path,
                        content: resource.content,
                        envelope: None,
                        thread_id: card.id.clone(),
                        message_id: message.id.clone(),
                        card_title: card_title.clone(),
                        from_handle: message.from_handle.clone(),
                        created_at: message.created_at.clone(),
                    });
                }
            }
        }
        artifacts.sort_by(|a, b| b.created_at.cmp(&a.created_at));
        collab.artifacts = artifacts;
        Ok(collab)
    }

    pub async fn create_collab(
        &self,
        name: &str,
        steerer_handles: &[String],
        roster_addresses: &[String],
        instructions: Option<&str>,
        artifacts: &[CollabArtifactDraft],
    ) -> Result<Collab> {
        let hub = self
            .hub_client()
            .context("not signed in — call auth_login first")?;
        let mut links = Vec::new();
        let mut files = Vec::new();
        for draft in artifacts {
            if draft.kind.eq_ignore_ascii_case("link") {
                links.push(link_artifact_for_hub(draft)?);
            } else {
                files.push(draft);
            }
        }
        // Omit plaintext instructions until we know encryption_mode (XOR).
        let collab = hub
            .create_collab(name, steerer_handles, roster_addresses, None, &links)
            .await?;
        if collab.encryption_mode == "app_envelope" {
            if let Some(text) = instructions.map(str::trim).filter(|s| !s.is_empty()) {
                hub.update_collab_instructions(&collab.id, Some(text))
                    .await?;
            }
        }
        if !files.is_empty() {
            let sealed = self.seal_collab_file_drafts(&collab, &files).await?;
            if !sealed.is_empty() {
                hub.add_collab_artifacts(&collab.id, &sealed).await?;
            }
        }
        self.get_collab(&collab.id).await
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

    async fn open_hub_collab_artifacts(&self, collab: &mut Collab) {
        for art in &mut collab.artifacts {
            if art.is_link() {
                art.strip_sealed();
                continue;
            }
            if let Some(env) = art.envelope.take() {
                match self.open_envelope_maybe_blob(&env).await {
                    Ok(plain) => match serde_json::from_slice::<MutandeBundle>(&plain) {
                        Ok(mut bundle) => {
                            self.surface_opened_bundle_resources(&mut bundle);
                            if let Some(resource) = bundle.resources.into_iter().next() {
                                if art.name.trim().is_empty() {
                                    art.name = resource.name.clone();
                                }
                                if art.mime.trim().is_empty() {
                                    art.mime = resource.mime;
                                }
                                if art.size.is_none() {
                                    art.size = resource.size;
                                }
                                art.path = resource.path;
                                art.content = resource.content;
                            }
                        }
                        Err(err) => {
                            tracing::warn!(error = %err, "collab file artifact bundle parse failed");
                        }
                    },
                    Err(err) => {
                        tracing::warn!(error = %err, "collab file artifact open failed");
                    }
                }
            } else if art.content.is_some() {
                let mut bundle = MutandeBundle {
                    resources: vec![BundleResource {
                        name: if art.name.trim().is_empty() {
                            art.display_label()
                        } else {
                            art.name.clone()
                        },
                        mime: if art.mime.trim().is_empty() {
                            "application/octet-stream".into()
                        } else {
                            art.mime.clone()
                        },
                        content: art.content.clone(),
                        path: None,
                        size: art.size,
                    }],
                    ..Default::default()
                };
                self.surface_opened_bundle_resources(&mut bundle);
                if let Some(resource) = bundle.resources.into_iter().next() {
                    art.name = resource.name;
                    art.mime = resource.mime;
                    art.size = resource.size;
                    art.path = resource.path;
                    art.content = resource.content;
                }
            }
            art.strip_sealed();
        }
    }

    async fn seal_collab_file_drafts(
        &self,
        collab: &Collab,
        files: &[&CollabArtifactDraft],
    ) -> Result<Vec<CollabArtifactSummary>> {
        let mut out = Vec::new();
        let e2e = collab.encryption_mode == "e2e";
        let keys = if e2e {
            Some(self.collab_steerer_pubkeys(collab).await?)
        } else {
            None
        };
        for draft in files {
            let Some(bytes) = draft.bytes.as_deref().filter(|b| !b.is_empty()) else {
                bail!("file artifact is missing bytes");
            };
            let name = draft
                .name
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .or_else(|| {
                    draft
                        .label
                        .as_deref()
                        .map(str::trim)
                        .filter(|s| !s.is_empty())
                })
                .unwrap_or("file")
                .to_string();
            let mime = draft
                .mime
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string);
            let label = draft
                .label
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string)
                .or_else(|| Some(name.clone()));
            let mut summary = CollabArtifactSummary {
                kind: "file".into(),
                label,
                url: None,
                name: name.clone(),
                mime: mime.clone().unwrap_or_default(),
                size: Some(bytes.len() as u64),
                path: None,
                content: None,
                envelope: None,
                thread_id: String::new(),
                message_id: String::new(),
                card_title: String::new(),
                from_handle: String::new(),
                created_at: String::new(),
            };
            if e2e {
                let bundle = bundle_for_blob_artifact(bytes, Some(&name), Some(&name));
                let plain = serde_json::to_vec(&bundle)?;
                let env = self
                    .seal_inline_or_blob(&plain, keys.as_ref().unwrap())
                    .await?;
                summary.envelope = Some(env);
            } else if let Ok(text) = std::str::from_utf8(bytes) {
                summary.content = Some(text.to_string());
            } else {
                use base64::Engine;
                summary.content = Some(base64::engine::general_purpose::STANDARD.encode(bytes));
            }
            if summary.mime.is_empty() {
                summary.mime = "application/octet-stream".into();
            }
            out.push(summary);
        }
        Ok(out)
    }
}

fn link_artifact_for_hub(draft: &CollabArtifactDraft) -> Result<CollabArtifactSummary> {
    let url = draft
        .url
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| anyhow::anyhow!("link artifact needs a url"))?;
    let (url, host) = parse_http_url(url)?;
    let label = draft
        .label
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .or_else(|| Some(host));
    Ok(CollabArtifactSummary {
        kind: "link".into(),
        label,
        url: Some(url),
        name: String::new(),
        mime: String::new(),
        size: None,
        path: None,
        content: None,
        envelope: None,
        thread_id: String::new(),
        message_id: String::new(),
        card_title: String::new(),
        from_handle: String::new(),
        created_at: String::new(),
    })
}

fn parse_http_url(raw: &str) -> Result<(String, String)> {
    let url = raw.trim();
    let lower = url.to_ascii_lowercase();
    if !(lower.starts_with("http://") || lower.starts_with("https://")) {
        bail!("url must be http or https");
    }
    if url.chars().any(|c| c.is_whitespace() || c == '<' || c == '"') {
        bail!("url is invalid");
    }
    let rest = if lower.starts_with("https://") {
        &url["https://".len()..]
    } else {
        &url["http://".len()..]
    };
    let host = rest
        .split(['/', '?', '#'])
        .next()
        .unwrap_or("")
        .trim_start_matches("www.");
    let host = host.split('@').next_back().unwrap_or(host);
    if host.is_empty() {
        bail!("url is invalid");
    }
    Ok((url.to_string(), host.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_http_url_accepts_https_and_rejects_javascript() {
        let (url, host) = parse_http_url("https://www.staging.example.com/app").unwrap();
        assert_eq!(url, "https://www.staging.example.com/app");
        assert_eq!(host, "staging.example.com");
        assert!(parse_http_url("javascript:alert(1)").is_err());
        assert!(parse_http_url("ftp://files.example.com").is_err());
    }

    #[test]
    fn link_draft_round_trip_sets_kind_and_url() {
        let art = link_artifact_for_hub(&CollabArtifactDraft {
            kind: "link".into(),
            label: Some("Docs".into()),
            url: Some("https://docs.example.com".into()),
            ..Default::default()
        })
        .unwrap();
        assert!(art.is_link());
        assert_eq!(art.url.as_deref(), Some("https://docs.example.com"));
        assert_eq!(art.display_label(), "Docs");
        let v = serde_json::to_value(&art).unwrap();
        let back: CollabArtifactSummary = serde_json::from_value(v).unwrap();
        assert!(back.is_link());
    }
}

