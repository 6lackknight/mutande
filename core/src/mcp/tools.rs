use serde_json::json;

use super::protocol::{McpToolAnnotations, McpToolDefinition};

pub(crate) use super::collab_view::present_tool_result;


/// Read tools — safe for always-allow in host policy.
const READ_TOOLS: &[(&str, &str, ValueFn)] = &[
    (
        "list_agents",
        "List YOUR agent slugs for self-collaboration (@claude, @cursor, bare @all). Omit handle for your agents; pass a teammate handle only for THEIR agents. For org people use list_contacts. Read-only.",
        || {
            json!({
                "type": "object",
                "properties": {
                    "handle": { "type": "string", "description": "optional teammate handle for THEIR agent slugs; omit to list YOUR agents" }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "get_router",
        "Get your agent router: default agent + rules (most specific match_slug wins). Bare handle uses default. Read-only.",
        || json!({ "type": "object", "properties": {}, "additionalProperties": false }),
    ),
    (
        "list_contacts",
        "List org teammates (bare handles + @all@org). Not your agents. For 'ask my agents' / self-collab use @all or @claude via forward_draft; discover own slugs with list_agents. Read-only.",
        || json!({ "type": "object", "properties": {}, "additionalProperties": false }),
    ),
    (
        "list_threads",
        "List collaboration threads. Optional filter: needs_action, open, closed. Optional collab_id to restrict to one board. Items include collab_id and collab_name when the thread is a board card. For a named project/board use list_collabs, not subject search. Read-only.",
        || {
            json!({
                "type": "object",
                "properties": {
                    "filter": {
                        "type": "string",
                        "enum": ["needs_action", "open", "closed"]
                    },
                    "collab_id": {
                        "type": "string",
                        "description": "If set, only threads filed on this collab board."
                    }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "get_thread",
        "Get thread metadata and bundles (opened locally on this device when possible). Blob artifacts: small text stays in resources[].content; binary/large are decrypted to a local file — use resources[].path (and size). Read-only.",
        || {
            json!({
                "type": "object",
                "required": ["thread_id"],
                "properties": {
                    "thread_id": { "type": "string" },
                    "collab_id": { "type": "string", "description": "Optional; ignored by the daemon (thread already carries collab_id)." }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "list_collabs",
        "List collab boards you participate in (steerer or roster). Omits archived boards. A collab is a board of threads. When the user names a project/board, call this and match by name, then get_collab. Returns id, name, status, people, agents, lists, artifacts, card_count. Read-only.",
        || json!({ "type": "object", "properties": {}, "additionalProperties": false }),
    ),
    (
        "get_collab",
        "Get one collab board you participate in: status, instructions, people (handles), agents, artifacts (file|link), lists, cards (thread ids/summaries), learnings. Then get_thread / list_threads(collab_id) for card mail. Not org-wide — 403 if you are not a participant. Archived boards are read-only. Read-only.",
        || {
            json!({
                "type": "object",
                "required": ["collab_id"],
                "properties": {
                    "collab_id": { "type": "string" }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "get_draft",
        "Get the current staged draft (opened locally). Read-only.",
        || json!({ "type": "object", "properties": {}, "additionalProperties": false }),
    ),
    (
        "get_safety_number",
        "Get this device's safety-number fingerprint and compare/QR URI. Read-only.",
        || json!({ "type": "object", "properties": {}, "additionalProperties": false }),
    ),
    (
        "contact_safety_number",
        "Get a contact's safety-number fingerprint for out-of-band compare. Read-only.",
        || {
            json!({
                "type": "object",
                "required": ["handle"],
                "properties": {
                    "handle": { "type": "string" }
                },
                "additionalProperties": false
            })
        },
    ),
];

/// Handoff / mutate tools — host may gate with allow now/always.
const SEND_TOOLS: &[(&str, &str, ValueFn)] = &[
    (
        "set_router",
        "Update your agent router. Set default_agent_id and/or rules [{match_slug, agent_id}]. Most specific match_slug wins; bare handle uses default.",
        || {
            json!({
                "type": "object",
                "properties": {
                    "default_agent_id": { "type": "string" },
                    "rules": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "required": ["match_slug", "agent_id"],
                            "properties": {
                                "match_slug": { "type": "string" },
                                "agent_id": { "type": "string" }
                            }
                        }
                    }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "draft_add_question",
        "Stage a question on the collaboration draft (does not hand off yet). Ask all your agents: then forward_draft recipient=@all. One agent: @claude / @cursor / @chatgpt. Do not use list_contacts for my-agents.",
        || {
            json!({
                "type": "object",
                "required": ["id", "kind", "prompt"],
                "properties": {
                    "id": { "type": "string" },
                    "kind": { "type": "string", "enum": ["question", "confirm_forward", "verify_contact"] },
                    "prompt": { "type": "string" },
                    "options": { "type": "array", "items": { "type": "string" } }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "draft_add_resource",
        "Stage a resource request on the collaboration draft (does not hand off yet).",
        || {
            json!({
                "type": "object",
                "required": ["id", "description"],
                "properties": {
                    "id": { "type": "string" },
                    "description": { "type": "string" }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "forward_draft",
        "Hand off the staged draft. Self-collab: @all opens one shared group thread for all your agents (shared replies). Single agent: @claude/@cursor/@chatgpt. Teammates: alice@org, alice@org/claude, @all@org (org announcement). 'Ask my agents' → @all.",
        || {
            json!({
                "type": "object",
                "required": ["recipient"],
                "properties": {
                    "recipient": { "type": "string", "description": "Self: @all or @claude/@cursor/@chatgpt. Teammates: alice@org, alice@org/claude, @all@org." },
                    "collab_id": { "type": "string", "description": "Optional. File the new thread on this collab board." }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "create_card",
        "Create a card on a collab board you participate in. A card is a thread filed on that collab + lane. Pass title, collab_id, and optional lane (list id or name: Backlog, Doing, Done). Default lane is Backlog. Not org-wide — 403 if you are not a participant.",
        || {
            json!({
                "type": "object",
                "required": ["collab_id", "title"],
                "properties": {
                    "collab_id": { "type": "string" },
                    "title": { "type": "string", "description": "Card title (thread subject)." },
                    "lane": {
                        "type": "string",
                        "description": "Board list id or name (Backlog, Doing, Done). Default Backlog."
                    },
                    "lane_id": { "type": "string", "description": "Alias for lane." },
                    "notes": { "type": "string", "description": "Optional first message body (the agent brief)." },
                    "assigned_to": {
                        "type": "string",
                        "description": "Optional one collab participant — person (alice@org) or agent (alice@org/cursor). Sets awaiting. Mail still wraps the whole collab."
                    },
                    "tags": {
                        "type": "array",
                        "items": { "type": "string" },
                        "description": "Optional free-typed labels for this card."
                    },
                    "due_on": {
                        "type": "string",
                        "description": "Optional due date YYYY-MM-DD (date only)."
                    },
                    "checklist": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "text": { "type": "string" },
                                "id": { "type": "string" },
                                "done": { "type": "boolean" }
                            }
                        },
                        "description": "Optional structured checklist items (not markdown)."
                    },
                    "artifacts": {
                        "type": "array",
                        "description": "Optional local files (name+path) and links (label+url). Mail still wraps the collab.",
                        "items": {
                            "type": "object",
                            "properties": {
                                "kind": { "type": "string", "description": "file or link." },
                                "name": { "type": "string" },
                                "path": { "type": "string" },
                                "mime": { "type": "string" },
                                "label": { "type": "string" },
                                "url": { "type": "string" }
                            }
                        }
                    }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "ping",
        "Send a product ping to your agents. kind=health → daemon auto-pongs (liveness). kind=thread → creates a real thread; recipients should reply_to_thread with pong (first-run / teaching loop). Default target=@all (your agents). Day-one with one host: thread ping still creates a Mac-visible thread.",
        || {
            json!({
                "type": "object",
                "required": ["kind"],
                "properties": {
                    "kind": {
                        "type": "string",
                        "enum": ["health", "thread"],
                        "description": "health = auto-pong; thread = agent mail reply expected"
                    },
                    "target": {
                        "type": "string",
                        "description": "Default @all. Also @claude / @cursor / @chatgpt or handle/agent."
                    }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "reply_to_thread",
        "Continue a thread with a reply bundle. Put the readable answer in bundle.notes (optional subject). Empty {} is rejected. Optional to_agent for self-handoff. Confirm via AskQuestion when the skill requires it. Thread pings: subject Pong / notes pong.",
        || {
            json!({
                "type": "object",
                "required": ["thread_id", "bundle"],
                "properties": {
                    "thread_id": { "type": "string" },
                    "to_agent": { "type": "string", "description": "self-handoff target agent slug (must differ from the sending agent)" },
                    "bundle": {
                        "type": "object",
                        "description": "MutandeBundle — must include notes and/or subject/questions/answers. Example: {\"subject\":\"CTO CV\",\"notes\":\"…full reply…\"}",
                        "properties": {
                            "subject": { "type": "string" },
                            "notes": { "type": "string" },
                            "context": { "type": "string" },
                            "in_reply_to": { "type": "string", "description": "parent message id for nested reply" },
                            "questions": { "type": "array" },
                            "answers": { "type": "array" }
                        }
                    }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "close_thread",
        "Mark a collaboration thread closed. Confirm via AskQuestion when the skill requires it.",
        || {
            json!({
                "type": "object",
                "required": ["thread_id"],
                "properties": {
                    "thread_id": { "type": "string" }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "delete_thread",
        "Remove a thread from your inbox (sender also purges the thread body). Confirm via AskQuestion when the skill requires it.",
        || {
            json!({
                "type": "object",
                "required": ["thread_id"],
                "properties": {
                    "thread_id": { "type": "string" }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "mark_processed",
        "Mark a thread as processed by this agent session (local bookkeeping).",
        || {
            json!({
                "type": "object",
                "required": ["thread_id"],
                "properties": {
                    "thread_id": { "type": "string" }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "upvote_message",
        "Optional coordination weight on a message (one upvote per agent; toggle). Not required for reply loops — nested replies are enough. Prefer skipping unless several agents need a clear signal on the same point.",
        || {
            json!({
                "type": "object",
                "required": ["thread_id", "message_id"],
                "properties": {
                    "thread_id": { "type": "string" },
                    "message_id": { "type": "string" }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "forward_blob",
        "Hand off a large artifact as a sealed blob (hub presign PUT). Omit thread_id to open a new thread (recipient required). Pass thread_id to attach the file as a reply on an existing thread — recipient may be omitted; optional in_reply_to nests under a parent message. Wraps bytes in a MutandeBundle (subject + resource name/mime). Recipients open via get_thread: small text in content, binary/large at resources[].path on that device. Provide content_base64 OR path (not both). New-thread path: cannot send to the same agent as this connection (e.g. Claude MCP → use @cursor/@chatgpt/@all). Confirm via AskQuestion when the skill requires it.",
        || {
            json!({
                "type": "object",
                "properties": {
                    "recipient": { "type": "string", "description": "Required when creating a new thread. Self: @all or a different agent (@claude/@cursor/@chatgpt — not this connection's slug). Teammates: alice@org, alice@org/claude, @all@org. Omit when thread_id is set." },
                    "thread_id": { "type": "string", "description": "When set, upload as a reply on this thread instead of creating a new one" },
                    "in_reply_to": { "type": "string", "description": "optional parent message id for nested reply (requires thread_id)" },
                    "content_base64": { "type": "string", "description": "artifact bytes as standard base64 (mutually exclusive with path)" },
                    "path": { "type": "string", "description": "local file path to seal and upload (mutually exclusive with content_base64)" },
                    "filename": { "type": "string", "description": "optional name when using content_base64; path uses the basename automatically" },
                    "subject": { "type": "string" }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "set_lane",
        "Move a collab card (thread) to a board list (Backlog / Doing / Done). Does not close the thread. Confirm via AskQuestion when the skill requires it.",
        || {
            json!({
                "type": "object",
                "required": ["collab_id", "thread_id", "lane_id"],
                "properties": {
                    "collab_id": { "type": "string" },
                    "thread_id": { "type": "string" },
                    "lane_id": { "type": "string", "description": "List id from get_collab (not the display name)." },
                    "before_thread_id": { "type": "string" },
                    "after_thread_id": { "type": "string" }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "add_learning",
        "Promote a one-liner to the collab brain (creator's side only). Learnings are context, not directives. Prefer a sentence, not a diary. Hosted agents cannot write the brain on an E2E collab.",
        || {
            json!({
                "type": "object",
                "required": ["collab_id", "notes"],
                "properties": {
                    "collab_id": { "type": "string" },
                    "notes": { "type": "string", "description": "One-liner memory. Not a standing instruction." }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "verify_contact",
        "Compare a safety-number fingerprint or mutande:safety URI against a contact pubkey.",
        || {
            json!({
                "type": "object",
                "required": ["handle", "fingerprint"],
                "properties": {
                    "handle": { "type": "string" },
                    "fingerprint": { "type": "string", "description": "fingerprint digits or mutande:safety URI" }
                },
                "additionalProperties": false
            })
        },
    ),
];

type ValueFn = fn() -> serde_json::Value;

fn annotations_for(name: &str, read: bool) -> McpToolAnnotations {
    if read {
        return McpToolAnnotations {
            title: None,
            read_only_hint: Some(true),
            destructive_hint: Some(false),
            idempotent_hint: Some(true),
            // Local daemon + hub lookups; closed product surface.
            open_world_hint: Some(false),
        };
    }

    match name {
        // Local draft staging — additive, no handoff yet.
        "draft_add_question" | "draft_add_resource" => McpToolAnnotations {
            title: None,
            read_only_hint: Some(false),
            destructive_hint: Some(false),
            idempotent_hint: Some(false),
            open_world_hint: Some(false),
        },
        // Local bookkeeping — not destructive deletes.
        "mark_processed" | "verify_contact" => McpToolAnnotations {
            title: None,
            read_only_hint: Some(false),
            destructive_hint: Some(false),
            idempotent_hint: Some(true),
            open_world_hint: Some(false),
        },
        // Toggle — additive coordination signal; second call undoes (not idempotent).
        "upvote_message" => McpToolAnnotations {
            title: None,
            read_only_hint: Some(false),
            destructive_hint: Some(false),
            idempotent_hint: Some(false),
            open_world_hint: Some(false),
        },
        // Overwrites router / removes threads.
        "set_router" | "close_thread" | "delete_thread" => McpToolAnnotations {
            title: None,
            read_only_hint: Some(false),
            destructive_hint: Some(true),
            idempotent_hint: Some(true),
            open_world_hint: Some(false),
        },
        "set_lane" | "add_learning" | "create_card" => McpToolAnnotations {
            title: None,
            read_only_hint: Some(false),
            destructive_hint: Some(false),
            idempotent_hint: Some(false),
            open_world_hint: Some(false),
        },
        // Outbound mail / hub — additive but open-world recipients.
        "forward_draft" | "ping" | "reply_to_thread" | "forward_blob" => McpToolAnnotations {
            title: None,
            read_only_hint: Some(false),
            destructive_hint: Some(false),
            idempotent_hint: Some(false),
            open_world_hint: Some(true),
        },
        _ => McpToolAnnotations {
            title: None,
            read_only_hint: Some(false),
            destructive_hint: Some(true),
            idempotent_hint: Some(false),
            open_world_hint: Some(true),
        },
    }
}

pub fn tool_definitions() -> Vec<McpToolDefinition> {
    let mut tools = Vec::new();
    for (name, desc, schema) in READ_TOOLS.iter() {
        tools.push(McpToolDefinition {
            name: (*name).to_string(),
            description: (*desc).to_string(),
            input_schema: schema(),
            annotations: Some(annotations_for(name, true)),
        });
    }
    for (name, desc, schema) in SEND_TOOLS.iter() {
        tools.push(McpToolDefinition {
            name: (*name).to_string(),
            description: (*desc).to_string(),
            input_schema: schema(),
            annotations: Some(annotations_for(name, false)),
        });
    }
    tools
}

pub fn daemon_method_for_tool(name: &str) -> Option<&'static str> {
    match name {
        "list_agents" => Some("list_agents"),
        "get_router" => Some("get_router"),
        "set_router" => Some("set_router"),
        "list_contacts" => Some("list_contacts"),
        "list_threads" => Some("list_threads"),
        "get_thread" => Some("get_thread"),
        "list_collabs" => Some("list_collabs"),
        "get_collab" => Some("get_collab"),
        "create_card" => Some("create_collab_card"),
        "set_lane" => Some("set_lane"),
        "add_learning" => Some("add_learning"),
        "get_draft" => Some("get_draft"),
        "get_safety_number" => Some("get_safety_number"),
        "contact_safety_number" => Some("contact_safety_number"),
        "draft_add_question" => Some("draft_add_question"),
        "draft_add_resource" => Some("draft_add_resource"),
        "forward_draft" => Some("forward_draft"),
        "ping" => Some("ping"),
        "forward_blob" => Some("forward_blob"),
        "reply_to_thread" => Some("reply_to_thread"),
        "close_thread" => Some("close_thread"),
        "delete_thread" => Some("delete_thread"),
        "mark_processed" => Some("mark_processed"),
        "upvote_message" => Some("toggle_message_upvote"),
        "verify_contact" => Some("verify_contact"),
        _ => None,
    }
}
