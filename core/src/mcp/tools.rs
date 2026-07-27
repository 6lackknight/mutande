use serde_json::json;

use super::protocol::McpToolDefinition;

/// Read tools — safe for always-allow in host policy.
const READ_TOOLS: &[(&str, &str, ValueFn)] = &[
    (
        "list_contacts",
        "List org contacts including @all@org. Read-only.",
        || json!({ "type": "object", "properties": {}, "additionalProperties": false }),
    ),
    (
        "list_threads",
        "List threads. Optional filter: needs_action, open, closed. Read-only.",
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
        "Get thread metadata and messages with locally decrypted bundles when this device can open them. Read-only.",
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
        "Get current encrypted draft (decrypted locally). Read-only.",
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

/// Send / mutate tools — require host allow now/always.
const SEND_TOOLS: &[(&str, &str, ValueFn)] = &[
    (
        "draft_add_question",
        "Stage a HumanDecision question on the draft. Does not send mail.",
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
        "Stage a resource request on the draft. Does not send mail.",
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
        "Send staged draft to a handle or @all@org. Creates a thread. Requires user confirmation.",
        || {
            json!({
                "type": "object",
                "required": ["recipient"],
                "properties": {
                    "recipient": { "type": "string", "description": "handle or @all@org" }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "reply_to_thread",
        "Reply on an existing thread with a bundle. Requires user confirmation.",
        || {
            json!({
                "type": "object",
                "required": ["thread_id", "bundle"],
                "properties": {
                    "thread_id": { "type": "string" },
                    "bundle": { "type": "object" }
                },
                "additionalProperties": false
            })
        },
    ),
    (
        "close_thread",
        "Mark a thread closed. Requires user confirmation.",
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
        "forward_blob",
        "Encrypt a large artifact, upload via hub presign PUT, and open a thread with blob_id envelope. Provide content_base64 or path. Requires user confirmation.",
        || {
            json!({
                "type": "object",
                "required": ["recipient"],
                "properties": {
                    "recipient": { "type": "string", "description": "handle or @all@org" },
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
        "verify_contact" => Some("verify_contact"),
        _ => None,
    }
}
