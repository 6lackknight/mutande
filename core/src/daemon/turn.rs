//! Turn-based awaiting fold, next_turn derivation, and hub turns mirror.

use std::collections::HashSet;

use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

use crate::hub_client::{ThreadMeta, YourStatus};

use super::state::{
    BundleAnswer, HumanDecision, MessageIntent, MutandeBundle, OpenedThreadDetail, OpenedThreadMessage,
    TurnActor, TurnEntry, TurnReason,
};

/// Hub mirror row: post-merge awaiting holder (blind courier).
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct HubTurnMirror {
    pub user_id: String,
    pub actor: TurnActor,
}

/// Fold opened messages into the current awaiting set.
///
/// When any message declares `next_turn`, use merge + strict question clearing.
/// Otherwise fall back to legacy heuristics (`thread_needs_human` / empty).
pub fn fold_awaiting(detail: &OpenedThreadDetail) -> Vec<TurnEntry> {
    let mut declared = false;
    let mut awaiting: Vec<TurnEntry> = Vec::new();

    for msg in &detail.messages {
        let Some(bundle) = msg.bundle.as_ref() else {
            continue;
        };
        if bundle.next_turn.is_empty() && bundle.intent.is_none() {
            continue;
        }
        declared = true;
        awaiting = merge_reply_into_awaiting(
            &awaiting,
            &msg.from_handle,
            &bundle.next_turn,
            &bundle.answers,
        );
    }

    if declared {
        return awaiting;
    }

    // Legacy: no next_turn/intent anywhere — caller uses heuristics.
    Vec::new()
}

/// Clear the replier's entries (strict for question reasons) and union new declarations.
pub fn merge_reply_into_awaiting(
    prior: &[TurnEntry],
    replier_address: &str,
    declared: &[TurnEntry],
    answers: &[BundleAnswer],
) -> Vec<TurnEntry> {
    let answer_ids: HashSet<&str> = answers.iter().map(|a| a.question_id.as_str()).collect();
    let replier_norm = normalize_address(replier_address);

    let mut kept: Vec<TurnEntry> = prior
        .iter()
        .filter(|e| {
            if !addresses_match(&e.address, &replier_norm)
                && !same_user_bare(&e.address, &replier_norm)
            {
                return true;
            }
            // Replier held this entry — clear unless strict question unmet.
            match &e.reason {
                Some(TurnReason::Question { question_id }) => {
                    // Keep only if answer missing (shouldn't happen after validation).
                    !answer_ids.contains(question_id.as_str())
                }
                _ => false,
            }
        })
        .cloned()
        .collect();

    for entry in declared {
        if !kept.iter().any(|k| turn_entry_eq(k, entry)) {
            kept.push(entry.clone());
        }
    }
    kept
}

fn turn_entry_eq(a: &TurnEntry, b: &TurnEntry) -> bool {
    normalize_address(&a.address) == normalize_address(&b.address)
        && a.actor == b.actor
        && a.reason == b.reason
}

/// Reject when the replier holds a question-reason turn without a matching answer.
pub fn validate_mandatory_answers(
    held: &[TurnEntry],
    replier_address: &str,
    answers: &[BundleAnswer],
) -> Result<()> {
    let answer_ids: HashSet<&str> = answers.iter().map(|a| a.question_id.as_str()).collect();
    let replier_norm = normalize_address(replier_address);
    for e in held {
        if !addresses_match(&e.address, &replier_norm)
            && !same_user_bare(&e.address, &replier_norm)
        {
            continue;
        }
        if let Some(TurnReason::Question { question_id }) = &e.reason {
            if !answer_ids.contains(question_id.as_str()) {
                bail!(
                    "open question `{question_id}` requires answers[].question_id before you can reply"
                );
            }
        }
    }
    Ok(())
}

/// Derive default `next_turn` when the tool omitted it.
pub fn derive_next_turn(
    intent: MessageIntent,
    bundle: &MutandeBundle,
    prior_awaiting: &[TurnEntry],
    sender_address: &str,
    recipient_address: Option<&str>,
    to_agent: Option<&str>,
    my_bare_handle: Option<&str>,
) -> Vec<TurnEntry> {
    match intent {
        MessageIntent::Status | MessageIntent::Fyi => Vec::new(),
        MessageIntent::Answer => {
            let sender_norm = normalize_address(sender_address);
            prior_awaiting
                .iter()
                .filter(|e| {
                    !addresses_match(&e.address, &sender_norm)
                        && !same_user_bare(&e.address, &sender_norm)
                })
                .cloned()
                .collect()
        }
        MessageIntent::Question => {
            // HumanDecision on bare handle → human actor with question reason.
            let mut out = Vec::new();
            for q in &bundle.questions {
                if q.kind == "question" {
                    let addr = recipient_address
                        .map(strip_agent)
                        .or_else(|| my_bare_handle.map(|s| s.to_string()))
                        .unwrap_or_else(|| strip_agent(sender_address));
                    // Bare-handle questions target the person.
                    if recipient_is_bare(recipient_address) || recipient_address.is_none() {
                        out.push(TurnEntry {
                            address: addr,
                            actor: TurnActor::Human,
                            reason: Some(TurnReason::Question {
                                question_id: q.id.clone(),
                            }),
                        });
                    } else if let Some(r) = recipient_address {
                        out.push(TurnEntry {
                            address: r.to_string(),
                            actor: TurnActor::Agent,
                            reason: Some(TurnReason::Question {
                                question_id: q.id.clone(),
                            }),
                        });
                    }
                } else if matches!(q.kind.as_str(), "confirm_forward" | "verify_contact") {
                    let addr = my_bare_handle
                        .map(|s| s.to_string())
                        .unwrap_or_else(|| strip_agent(sender_address));
                    out.push(TurnEntry {
                        address: addr,
                        actor: TurnActor::Human,
                        reason: Some(TurnReason::Review),
                    });
                }
            }
            if out.is_empty() {
                if let Some(r) = recipient_address {
                    out.push(TurnEntry {
                        address: r.to_string(),
                        actor: if recipient_is_bare(Some(r)) {
                            TurnActor::Human
                        } else {
                            TurnActor::Agent
                        },
                        reason: Some(TurnReason::Question {
                            question_id: bundle
                                .questions
                                .first()
                                .map(|q| q.id.clone())
                                .unwrap_or_else(|| "q".into()),
                        }),
                    });
                }
            }
            out
        }
        MessageIntent::Handoff => {
            if let Some(to) = to_agent.map(str::trim).filter(|s| !s.is_empty()) {
                let slug = to.strip_prefix('@').unwrap_or(to);
                let addr = my_bare_handle
                    .map(|h| format!("{h}/{slug}"))
                    .unwrap_or_else(|| format!("@{slug}"));
                return vec![TurnEntry {
                    address: addr,
                    actor: TurnActor::Agent,
                    reason: Some(TurnReason::Handoff),
                }];
            }
            if let Some(r) = recipient_address {
                return vec![TurnEntry {
                    address: r.to_string(),
                    actor: TurnActor::Agent,
                    reason: Some(TurnReason::Handoff),
                }];
            }
            Vec::new()
        }
    }
}

/// Map awaiting TurnEntry addresses to hub `{user_id, actor}` using thread participants.
/// Caller supplies a resolver from bare handle → user_id.
pub fn hub_turns_mirror(
    awaiting: &[TurnEntry],
    resolve_user_id: impl Fn(&str) -> Option<String>,
) -> Vec<HubTurnMirror> {
    let mut out: Vec<HubTurnMirror> = Vec::new();
    for e in awaiting {
        let bare = strip_agent(&e.address);
        let Some(user_id) = resolve_user_id(&bare) else {
            continue;
        };
        if out
            .iter()
            .any(|h| h.user_id == user_id && h.actor == e.actor)
        {
            continue;
        }
        // Prefer human actor if both present for same user.
        if let Some(existing) = out.iter_mut().find(|h| h.user_id == user_id) {
            if e.actor == TurnActor::Human {
                existing.actor = TurnActor::Human;
            }
            continue;
        }
        out.push(HubTurnMirror {
            user_id,
            actor: e.actor,
        });
    }
    out
}

/// Mac UI: Needs you when awaiting has human actor for my handle.
pub fn your_status_from_awaiting(
    awaiting: &[TurnEntry],
    my_bare_handle: &str,
    for_agent_slug: Option<&str>,
) -> YourStatus {
    if awaiting.is_empty() {
        return YourStatus::Replied;
    }
    let my = normalize_address(my_bare_handle);
    if let Some(slug) = for_agent_slug {
        let agent_addr = format!("{my}/{slug}");
        let short = format!("@{slug}");
        let pending = awaiting.iter().any(|e| {
            e.actor == TurnActor::Agent
                && (addresses_match(&e.address, &agent_addr)
                    || addresses_match(&e.address, &short)
                    || (same_user_bare(&e.address, &my) && agent_suffix_of(&e.address) == Some(slug)))
        });
        return if pending {
            YourStatus::Pending
        } else {
            YourStatus::Replied
        };
    }
    // Human / Mac UI
    let needs_human = awaiting.iter().any(|e| {
        e.actor == TurnActor::Human
            && (addresses_match(&e.address, &my) || same_user_bare(&e.address, &my))
    });
    if needs_human {
        YourStatus::Pending
    } else if !awaiting.is_empty() {
        YourStatus::Replied // waiting on agents
    } else {
        YourStatus::Replied
    }
}

pub fn thread_has_declared_turns(detail: &OpenedThreadDetail) -> bool {
    detail.messages.iter().any(|m| {
        m.bundle
            .as_ref()
            .is_some_and(|b| !b.next_turn.is_empty() || b.intent.is_some())
    })
}

pub fn normalize_address(addr: &str) -> String {
    addr.trim().to_ascii_lowercase()
}

pub fn strip_agent(addr: &str) -> String {
    let a = addr.trim();
    if let Some((bare, _)) = a.rsplit_once('/') {
        return bare.to_string();
    }
    if a.starts_with('@') && !a[1..].contains('@') {
        // @slug — bare handle unknown
        return a.to_string();
    }
    a.to_string()
}

fn agent_suffix_of(addr: &str) -> Option<&str> {
    addr.rsplit_once('/').map(|(_, s)| s)
}

fn recipient_is_bare(recipient: Option<&str>) -> bool {
    match recipient {
        None => true,
        Some(r) => {
            let r = r.trim();
            !r.contains('/') && !(r.starts_with('@') && !r[1..].contains('@'))
        }
    }
}

fn addresses_match(a: &str, b: &str) -> bool {
    normalize_address(a) == normalize_address(b)
}

/// Same user when both are bare or one is bare and the other is handle/agent.
fn same_user_bare(a: &str, b: &str) -> bool {
    let a_bare = strip_agent(a).to_ascii_lowercase();
    let b_bare = strip_agent(b).to_ascii_lowercase();
    if a_bare.starts_with('@') || b_bare.starts_with('@') {
        return false;
    }
    a_bare == b_bare
}

/// Ensure bundle carries version 2 when using new fields.
pub fn stamp_bundle_v2(bundle: &mut MutandeBundle) {
    if bundle.version.unwrap_or(1) < 2 {
        bundle.version = Some(2);
    }
}

/// Prepare outgoing bundle: require intent, fill next_turn, stamp version.
pub fn prepare_outgoing_bundle(
    bundle: &mut MutandeBundle,
    intent: MessageIntent,
    prior_awaiting: &[TurnEntry],
    sender_address: &str,
    recipient_address: Option<&str>,
    to_agent: Option<&str>,
    my_bare_handle: Option<&str>,
) -> Result<()> {
    bundle.intent = Some(intent);
    stamp_bundle_v2(bundle);
    if bundle.next_turn.is_empty() {
        bundle.next_turn = derive_next_turn(
            intent,
            bundle,
            prior_awaiting,
            sender_address,
            recipient_address,
            to_agent,
            my_bare_handle,
        );
    }
    Ok(())
}

/// Resolve held question turns for the sender from prior awaiting.
pub fn held_by_address<'a>(awaiting: &'a [TurnEntry], address: &str) -> Vec<&'a TurnEntry> {
    let norm = normalize_address(address);
    awaiting
        .iter()
        .filter(|e| addresses_match(&e.address, &norm) || same_user_bare(&e.address, &norm))
        .collect()
}

#[allow(dead_code)]
pub fn apply_awaiting_to_thread_meta(
    thread: &mut ThreadMeta,
    awaiting: Vec<TurnEntry>,
    my_bare: Option<&str>,
    agent_slug: Option<&str>,
) {
    thread.awaiting = Some(awaiting.clone());
    if let Some(bare) = my_bare {
        thread.your_status = Some(your_status_from_awaiting(&awaiting, bare, agent_slug));
    }
}

/// Synthetic human-decision for task gate (daemon-local; not necessarily in bundle).
pub fn task_gate_decision(from_handle: &str, objective: &str, message_id: &str) -> HumanDecision {
    HumanDecision {
        id: format!("task_gate:{message_id}"),
        kind: "confirm_forward".into(),
        title: Some("Allow agent task?".into()),
        prompt: format!(
            "@{from} asks your agent to: {objective} — allow?",
            from = from_handle.trim_start_matches('@'),
            objective = objective
        ),
        options: Some(vec![
            super::state::DecisionOption::Structured {
                id: "allow".into(),
                label: "Allow".into(),
            },
            super::state::DecisionOption::Structured {
                id: "deny".into(),
                label: "Deny".into(),
            },
        ]),
        allow_multiple: Some(false),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hub_client::{ThreadKind, ThreadStatus};

    fn empty_thread() -> OpenedThreadDetail {
        OpenedThreadDetail {
            thread: ThreadMeta {
                id: "t1".into(),
                kind: ThreadKind::Direct,
                status: ThreadStatus::Open,
                from: "alice@acme/cursor".into(),
                from_user_id: "u1".into(),
                from_agent_id: None,
                audience: "bob@acme/claude".into(),
                audience_agent_id: None,
                audience_wire_path: None,
                org_id: "o1".into(),
                participant_count: 2,
                reply_count: 0,
                your_status: None,
                created_at: "t".into(),
                updated_at: "t".into(),
                encryption_mode: None,
                downgrade_point: None,
                enterprise_listing_id: None,
                last_from: None,
                last_subject: None,
                last_preview: None,
                awaiting: None,
            },
            messages: vec![],
            pending_downgrade: None,
            pending_task_approvals: None,
        }
    }

    #[test]
    fn merge_clears_replier_and_unions() {
        let prior = vec![
            TurnEntry {
                address: "alice@acme/cursor".into(),
                actor: TurnActor::Agent,
                reason: Some(TurnReason::Handoff),
            },
            TurnEntry {
                address: "bob@acme/claude".into(),
                actor: TurnActor::Agent,
                reason: Some(TurnReason::Handoff),
            },
        ];
        let declared = vec![TurnEntry {
            address: "bob@acme".into(),
            actor: TurnActor::Human,
            reason: Some(TurnReason::Review),
        }];
        let next = merge_reply_into_awaiting(&prior, "alice@acme/cursor", &declared, &[]);
        assert_eq!(next.len(), 2);
        assert!(next.iter().any(|e| e.address == "bob@acme/claude"));
        assert!(next.iter().any(|e| e.actor == TurnActor::Human));
    }

    #[test]
    fn strict_question_requires_answer() {
        let held = vec![TurnEntry {
            address: "alice@acme".into(),
            actor: TurnActor::Human,
            reason: Some(TurnReason::Question {
                question_id: "q1".into(),
            }),
        }];
        assert!(validate_mandatory_answers(&held, "alice@acme/cursor", &[]).is_err());
        assert!(validate_mandatory_answers(
            &held,
            "alice@acme/cursor",
            &[BundleAnswer {
                question_id: "q1".into(),
                answer: "yes".into(),
            }]
        )
        .is_ok());
    }

    #[test]
    fn fold_uses_declared_next_turn() {
        let mut detail = empty_thread();
        detail.messages.push(OpenedThreadMessage {
            id: "m1".into(),
            thread_id: "t1".into(),
            from_user_id: "u1".into(),
            from_handle: "alice@acme/cursor".into(),
            created_at: "t".into(),
            sender_only: None,
            parent_message_id: None,
            bundle: Some(MutandeBundle {
                intent: Some(MessageIntent::Handoff),
                next_turn: vec![TurnEntry {
                    address: "bob@acme/claude".into(),
                    actor: TurnActor::Agent,
                    reason: Some(TurnReason::Handoff),
                }],
                ..Default::default()
            }),
            envelope: None,
            open_error: None,
            upvotes: None,
            receipts: None,
            task_pending_approval: None,
        });
        let awaiting = fold_awaiting(&detail);
        assert_eq!(awaiting.len(), 1);
        assert_eq!(awaiting[0].address, "bob@acme/claude");
    }
}
