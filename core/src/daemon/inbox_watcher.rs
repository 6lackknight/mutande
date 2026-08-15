//! Background hub metadata poller — emits [EventHub] events when inbox fingerprint changes.
//!
//! Does **not** decrypt bundles; full enrichment still happens on client-driven `list_threads`.

use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::Duration;

use crate::hub_client::ThreadMeta;

use super::event_hub::EventHub;
use super::state::DaemonState;

pub const DEFAULT_POLL_INTERVAL: Duration = Duration::from_secs(5);
const MAX_BACKOFF: Duration = Duration::from_secs(60);

/// Stable fingerprint of hub-visible thread metadata (no snippets).
pub fn inbox_fingerprint(threads: &[ThreadMeta]) -> String {
    let mut map = BTreeMap::new();
    for t in threads {
        let your = t
            .your_status
            .as_ref()
            .map(|s| format!("{s:?}"))
            .unwrap_or_default();
        map.insert(
            t.id.clone(),
            format!(
                "{}|{:?}|{}|{}",
                t.updated_at, t.status, t.reply_count, your
            ),
        );
    }
    let mut out = String::new();
    for (id, sig) in map {
        out.push_str(&id);
        out.push('=');
        out.push_str(&sig);
        out.push(';');
    }
    out
}

/// Apply one watcher tick: return true if an event was published.
pub fn apply_tick(
    hub: &EventHub,
    last: &mut Option<String>,
    threads: &[ThreadMeta],
) -> bool {
    let fp = inbox_fingerprint(threads);
    match last {
        None => {
            *last = Some(fp);
            false
        }
        Some(prev) if *prev == fp => false,
        Some(prev) => {
            *prev = fp;
            hub.publish_inbox_changed();
            true
        }
    }
}

pub async fn run(state: Arc<DaemonState>, interval: Duration) {
    let mut last: Option<String> = None;
    let mut sleep_for = interval;
    tracing::info!(
        secs = interval.as_secs(),
        "inbox watcher started (hub metadata poll)"
    );
    loop {
        tokio::time::sleep(sleep_for).await;
        match state.list_threads_meta().await {
            Ok(threads) => {
                sleep_for = interval;
                let published = apply_tick(state.event_hub(), &mut last, &threads);
                if published {
                    tracing::debug!(
                        threads = threads.len(),
                        "inbox watcher detected change"
                    );
                }
            }
            Err(err) => {
                tracing::debug!(error = %err, "inbox watcher tick failed");
                sleep_for = (sleep_for * 2).min(MAX_BACKOFF);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hub_client::{ThreadKind, ThreadStatus, YourStatus};

    fn meta(id: &str, updated: &str, replies: u32) -> ThreadMeta {
        ThreadMeta {
            id: id.into(),
            kind: ThreadKind::Direct,
            status: ThreadStatus::Open,
            from: "a@acme".into(),
            from_user_id: "u1".into(),
            from_agent_id: None,
            audience: "b@acme".into(),
            audience_agent_id: None,
            audience_wire_path: None,
            org_id: "o1".into(),
            participant_count: 2,
            reply_count: replies,
            your_status: Some(YourStatus::Pending),
            created_at: "2026-01-01T00:00:00Z".into(),
            updated_at: updated.into(),
            encryption_mode: None,
            downgrade_point: None,
            enterprise_listing_id: None,
            last_from: None,
            last_subject: None,
            last_preview: None,
            awaiting: None,
            collab_id: None,
            lane_id: None,
            lane_position: None,
            assigned_to: None,
            watchers: None,
            collab_name: None,
        }
    }

    #[test]
    fn unchanged_fingerprint_no_emit() {
        let hub = EventHub::new();
        let mut last = None;
        let threads = vec![meta("t1", "2026-01-01T00:00:00Z", 0)];
        assert!(!apply_tick(&hub, &mut last, &threads));
        assert!(!apply_tick(&hub, &mut last, &threads));
        assert_eq!(hub.receiver_count(), 0);
    }

    #[test]
    fn updated_at_bump_emits_once() {
        let hub = EventHub::new();
        let mut rx = hub.subscribe();
        let mut last = None;
        let a = vec![meta("t1", "2026-01-01T00:00:00Z", 0)];
        assert!(!apply_tick(&hub, &mut last, &a));
        let b = vec![meta("t1", "2026-01-01T00:00:05Z", 1)];
        assert!(apply_tick(&hub, &mut last, &b));
        let ev = rx.try_recv().unwrap();
        assert_eq!(ev.event, "inbox_changed");
        assert_eq!(ev.revision, 1);
        assert!(rx.try_recv().is_err());
    }

    #[test]
    fn fingerprint_order_independent() {
        let a = vec![
            meta("t2", "b", 1),
            meta("t1", "a", 0),
        ];
        let b = vec![
            meta("t1", "a", 0),
            meta("t2", "b", 1),
        ];
        assert_eq!(inbox_fingerprint(&a), inbox_fingerprint(&b));
    }
}
