use serde_json::json;

use super::protocol::McpToolDefinition;

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
        "List collaboration threads. Optional filter: needs_action, open, closed. Read-only.",
        || {
            json!({
                "type": "object",
                "properties": {
                    "filter": {
                        "type": "string",
                        "enum": ["needs_action", "open", "closed"]
                    }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "get_thread",
        "Get thread metadata and bundles (opened locally on this device when possible). Read-only.",
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
        "Hand off the staged draft. Self-collab: @all fans out one thread per other registered agent (excludes sender); result has recipients + thread_ids (parallel arrays) and thread_id (first only — do not treat that as the full fanout). Single agent: @claude/@cursor/@chatgpt. Teammates: alice@org, alice@org/claude, @all@org. 'Ask my agents' → @all.",
        || {
            json!({
                "type": "object",
                "required": ["recipient"],
                "properties": {
                    "recipient": { "type": "string", "description": "Self: @all or @claude/@cursor/@chatgpt. Teammates: alice@org, alice@org/claude, @all@org." }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "reply_to_thread",
        "Continue a thread with a reply bundle. Optional to_agent for self-handoff to another of your agents (e.g. claude). Confirm via AskQuestion when the skill requires it.",
        || {
            json!({
                "type": "object",
                "required": ["thread_id", "bundle"],
                "properties": {
                    "thread_id": { "type": "string" },
                    "to_agent": { "type": "string", "description": "self-handoff target agent slug (must differ from the sending agent)" },
                    "bundle": { "type": "object" }
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
        "Signal interest or agreement on a thread message (one upvote per agent; toggle). Use for multi-agent coordination weight — nested replies handle structure.",
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
        "Hand off a large artifact as a sealed blob on a new thread (hub presign PUT). Provide content_base64 or path. Same recipients as forward_draft. Confirm via AskQuestion when the skill requires it.",
        || {
            json!({
                "type": "object",
                "required": ["recipient"],
                "properties": {
                    "recipient": { "type": "string", "description": "Self: @all or @claude/@cursor/@chatgpt. Teammates: alice@org, alice@org/claude, @all@org." },
                    "content_base64": { "type": "string" },
                    "path": { "type": "string", "description": "local file path to seal and upload" },
                    "subject": { "type": "string" }
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

pub fn tool_definitions() -> Vec<McpToolDefinition> {
    let mut tools = Vec::new();
    for (name, desc, schema) in READ_TOOLS.iter().chain(SEND_TOOLS.iter()) {
        tools.push(McpToolDefinition {
            name: (*name).to_string(),
            description: (*desc).to_string(),
            input_schema: schema(),
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
        "get_draft" => Some("get_draft"),
        "get_safety_number" => Some("get_safety_number"),
        "contact_safety_number" => Some("contact_safety_number"),
        "draft_add_question" => Some("draft_add_question"),
        "draft_add_resource" => Some("draft_add_resource"),
        "forward_draft" => Some("forward_draft"),
        "forward_blob" => Some("forward_blob"),
        "reply_to_thread" => Some("reply_to_thread"),
        "close_thread" => Some("close_thread"),
        "mark_processed" => Some("mark_processed"),
        "upvote_message" => Some("toggle_message_upvote"),
        "verify_contact" => Some("verify_contact"),
        _ => None,
    }
}
