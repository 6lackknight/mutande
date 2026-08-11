//! Fan-out bus for daemon → UI inbox change notifications (metadata only).

use std::sync::atomic::{AtomicU64, Ordering};

use serde::Serialize;
use tokio::sync::broadcast;

/// Pushed to WebSocket subscribers — never includes decrypted content.
#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct InboxChangedEvent {
    pub event: &'static str,
    pub revision: u64,
    pub at: String,
}

impl InboxChangedEvent {
    pub fn new(revision: u64) -> Self {
        Self {
            event: "inbox_changed",
            revision,
            at: chrono_like_now(),
        }
    }
}

/// RFC3339-ish UTC timestamp without pulling chrono.
fn chrono_like_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    // Enough for clients; precise formatting is optional.
    format!("{secs}")
}

pub struct EventHub {
    tx: broadcast::Sender<InboxChangedEvent>,
    revision: AtomicU64,
}

impl EventHub {
    pub fn new() -> Self {
        let (tx, _) = broadcast::channel(64);
        Self {
            tx,
            revision: AtomicU64::new(0),
        }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<InboxChangedEvent> {
        self.tx.subscribe()
    }

    pub fn receiver_count(&self) -> usize {
        self.tx.receiver_count()
    }

    /// Bump revision and notify all subscribers.
    pub fn publish_inbox_changed(&self) -> InboxChangedEvent {
        let revision = self.revision.fetch_add(1, Ordering::SeqCst) + 1;
        let event = InboxChangedEvent::new(revision);
        let _ = self.tx.send(event.clone());
        tracing::debug!(
            revision,
            subscribers = self.tx.receiver_count(),
            "inbox_changed published"
        );
        event
    }
}

impl Default for EventHub {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn fan_out_to_multiple_subscribers() {
        let hub = EventHub::new();
        let mut a = hub.subscribe();
        let mut b = hub.subscribe();
        let ev = hub.publish_inbox_changed();
        assert_eq!(ev.revision, 1);
        assert_eq!(a.recv().await.unwrap().revision, 1);
        assert_eq!(b.recv().await.unwrap().revision, 1);
        let ev2 = hub.publish_inbox_changed();
        assert_eq!(ev2.revision, 2);
    }

    #[tokio::test]
    async fn dropped_receiver_does_not_block() {
        let hub = EventHub::new();
        let mut keep = hub.subscribe();
        {
            let _drop_me = hub.subscribe();
        }
        hub.publish_inbox_changed();
        assert_eq!(keep.recv().await.unwrap().event, "inbox_changed");
    }
}
