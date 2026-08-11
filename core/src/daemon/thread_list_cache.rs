//! Disk cache for Mac UI `list_threads` enrichment (snippets + Needs you).
//!
//! Keyed by thread id + hub `updated_at` so a background poll skips re-decrypt
//! when nothing changed, while new mail still triggers a fresh open.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::PathBuf;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use crate::hub_client::{ThreadMeta, YourStatus};

use super::expand_path;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
struct EnrichmentEntry {
    updated_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    your_status: Option<YourStatus>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_from: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_subject: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    last_preview: Option<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct EnrichmentFile {
    #[serde(default)]
    threads: HashMap<String, EnrichmentEntry>,
}

pub struct ThreadListEnrichmentCache {
    path: PathBuf,
    data: EnrichmentFile,
}

impl ThreadListEnrichmentCache {
    pub fn load_default() -> Self {
        Self::load(expand_path("~/.mutande/thread_list_enrichment.json"))
    }

    pub fn load(path: PathBuf) -> Self {
        let data = fs::read_to_string(&path)
            .ok()
            .and_then(|raw| serde_json::from_str(&raw).ok())
            .unwrap_or_default();
        Self { path, data }
    }

    pub fn load_in_memory() -> Self {
        Self {
            path: PathBuf::from("/dev/null"),
            data: EnrichmentFile::default(),
        }
    }

    /// Apply cached list fields when hub `updated_at` matches. Returns true on hit.
    pub fn apply_if_fresh(&self, thread: &mut ThreadMeta) -> bool {
        let Some(entry) = self.data.threads.get(&thread.id) else {
            return false;
        };
        if entry.updated_at != thread.updated_at {
            return false;
        }
        thread.your_status = entry.your_status;
        thread.last_from = entry.last_from.clone();
        thread.last_subject = entry.last_subject.clone();
        thread.last_preview = entry.last_preview.clone();
        true
    }

    pub fn record(&mut self, thread: &ThreadMeta) {
        self.data.threads.insert(
            thread.id.clone(),
            EnrichmentEntry {
                updated_at: thread.updated_at.clone(),
                your_status: thread.your_status,
                last_from: thread.last_from.clone(),
                last_subject: thread.last_subject.clone(),
                last_preview: thread.last_preview.clone(),
            },
        );
    }

    pub fn prune(&mut self, keep: &HashSet<String>) {
        self.data
            .threads
            .retain(|id, _| keep.contains(id.as_str()));
    }

    pub fn save(&self) -> Result<()> {
        if self.path.as_os_str().is_empty() || self.path == PathBuf::from("/dev/null") {
            return Ok(());
        }
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("create {}", parent.display()))?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = fs::set_permissions(parent, fs::Permissions::from_mode(0o700));
            }
        }
        let json = serde_json::to_string_pretty(&self.data)?;
        fs::write(&self.path, json).with_context(|| format!("write {}", self.path.display()))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&self.path, fs::Permissions::from_mode(0o600));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hub_client::{ThreadKind, ThreadStatus};

    #[test]
    fn apply_skips_stale_updated_at() {
        let mut cache = ThreadListEnrichmentCache::load_in_memory();
        let mut thread = ThreadMeta {
            id: "t1".into(),
            kind: ThreadKind::Direct,
            status: ThreadStatus::Open,
            from: "a@x".into(),
            from_user_id: "u1".into(),
            from_agent_id: None,
            audience: "b@x".into(),
            audience_agent_id: None,
            audience_wire_path: None,
            org_id: "o1".into(),
            participant_count: 2,
            reply_count: 0,
            your_status: None,
            created_at: "2026-01-01T00:00:00Z".into(),
            updated_at: "2026-01-02T00:00:00Z".into(),
            encryption_mode: None,
            downgrade_point: None,
                enterprise_listing_id: None,
                last_from: None,
            last_subject: None,
            last_preview: None,
        };
        thread.last_preview = Some("hello".into());
        thread.your_status = Some(YourStatus::Pending);
        cache.record(&thread);

        thread.updated_at = "2026-01-03T00:00:00Z".into();
        thread.last_preview = None;
        assert!(!cache.apply_if_fresh(&mut thread));
        assert!(thread.last_preview.is_none());

        thread.updated_at = "2026-01-02T00:00:00Z".into();
        assert!(cache.apply_if_fresh(&mut thread));
        assert_eq!(thread.last_preview.as_deref(), Some("hello"));
        assert_eq!(thread.your_status, Some(YourStatus::Pending));
    }
}
