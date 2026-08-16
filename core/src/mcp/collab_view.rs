//! Agent-facing collab payload — participants see the board object, not hub internals.

use serde_json::{Value, json};

fn lower(s: &str) -> String {
    s.trim().to_ascii_lowercase()
}

fn str_val(v: &Value, key: &str) -> String {
    v.get(key)
        .and_then(|x| x.as_str())
        .unwrap_or("")
        .to_string()
}

fn opt_str(v: &Value, key: &str) -> Option<String> {
    v.get(key)
        .and_then(|x| x.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(ToString::to_string)
}

fn present_people(raw: &Value) -> Vec<Value> {
    raw.get("steerers")
        .and_then(|s| s.as_array())
        .into_iter()
        .flatten()
        .filter_map(|s| {
            let handle = opt_str(s, "handle").map(|h| lower(&h))?;
            Some(json!({ "handle": handle }))
        })
        .collect()
}

fn present_agents(raw: &Value) -> Vec<Value> {
    raw.get("roster")
        .and_then(|s| s.as_array())
        .into_iter()
        .flatten()
        .filter_map(|r| {
            let address = opt_str(r, "address").map(|a| lower(&a))?;
            let mut obj = json!({ "address": address });
            if let Some(t) = opt_str(r, "transport") {
                obj["transport"] = json!(t);
            }
            Some(obj)
        })
        .collect()
}

fn present_lists(raw: &Value) -> Value {
    raw.get("lists").cloned().unwrap_or(json!([]))
}

fn present_cards(raw: &Value) -> Vec<Value> {
    raw.get("cards")
        .and_then(|c| c.as_array())
        .into_iter()
        .flatten()
        .filter_map(|c| {
            let id = opt_str(c, "id")?;
            let subject = opt_str(c, "last_subject").or_else(|| opt_str(c, "subject"));
            Some(json!({
                "thread_id": id,
                "id": opt_str(c, "id"),
                "subject": subject,
                "lane_id": opt_str(c, "lane_id"),
                "lane_position": c.get("lane_position"),
                "status": opt_str(c, "status"),
                "assigned_to": opt_str(c, "assigned_to").map(|a| lower(&a)),
                "tags": c.get("tags"),
                "due_on": opt_str(c, "due_on"),
                "checklist": c.get("checklist"),
                "from": opt_str(c, "from").map(|a| lower(&a)),
                "audience": opt_str(c, "audience").map(|a| lower(&a)),
                "your_status": opt_str(c, "your_status"),
                "updated_at": opt_str(c, "updated_at"),
            }))
        })
        .collect()
}

fn present_artifacts(raw: &Value) -> Vec<Value> {
    raw.get("artifacts")
        .and_then(|a| a.as_array())
        .into_iter()
        .flatten()
        .map(|a| {
            let kind = opt_str(a, "kind")
                .map(|k| k.to_ascii_lowercase())
                .filter(|k| k == "link" || k == "file")
                .unwrap_or_else(|| "file".into());
            let mut obj = json!({
                "kind": kind,
                "label": opt_str(a, "label"),
                "name": opt_str(a, "name"),
                "mime": opt_str(a, "mime"),
                "size": a.get("size"),
                "thread_id": opt_str(a, "thread_id").filter(|s| !s.is_empty()),
                "card_title": opt_str(a, "card_title").filter(|s| !s.is_empty()),
            });
            if obj["kind"] == "link" {
                obj["url"] = json!(opt_str(a, "url"));
            } else {
                if let Some(path) = opt_str(a, "path") {
                    obj["path"] = json!(path);
                }
                if obj.get("path").and_then(|p| p.as_str()).is_none() {
                    if let Some(content) = opt_str(a, "content") {
                        obj["content"] = json!(content);
                    }
                }
            }
            obj
        })
        .collect()
}

fn present_learnings(raw: &Value) -> Vec<Value> {
    raw.get("learnings")
        .and_then(|l| l.as_array())
        .into_iter()
        .flatten()
        .map(|l| {
            json!({
                "id": opt_str(l, "id"),
                "created_at": opt_str(l, "created_at").or_else(|| opt_str(l, "at")),
                "from_handle": opt_str(l, "from_handle").map(|h| lower(&h)),
                "notes": opt_str(l, "notes"),
                "sealed": l.get("sealed"),
            })
        })
        .collect()
}

/// Board object for MCP: name, instructions, people, agents, artifacts, cards.
pub fn present_collab(raw: &Value) -> Value {
    let cards = present_cards(raw);
    let card_count = raw
        .get("card_count")
        .and_then(|n| n.as_u64())
        .unwrap_or(cards.len() as u64);
    let status = if opt_str(raw, "status").as_deref() == Some("archived") {
        "archived"
    } else {
        "open"
    };
    json!({
        "id": str_val(raw, "id"),
        "name": str_val(raw, "name"),
        "status": status,
        "instructions": opt_str(raw, "instructions"),
        "encryption_mode": opt_str(raw, "encryption_mode"),
        "people": present_people(raw),
        "agents": present_agents(raw),
        "lists": present_lists(raw),
        "cards": cards,
        "artifacts": present_artifacts(raw),
        "learnings": present_learnings(raw),
        "card_count": card_count,
        "memory_thread_id": opt_str(raw, "memory_thread_id"),
    })
}

pub fn present_tool_result(tool: &str, daemon_json: Value) -> Value {
    match tool {
        "get_collab" => {
            let raw = daemon_json.get("collab").unwrap_or(&daemon_json);
            json!({ "collab": present_collab(raw) })
        }
        "list_collabs" => {
            let collabs = daemon_json
                .get("collabs")
                .and_then(|c| c.as_array())
                .into_iter()
                .flatten()
                .filter(|c| opt_str(c, "status").as_deref() != Some("archived"))
                .map(present_collab)
                .collect::<Vec<_>>();
            json!({ "collabs": collabs })
        }
        _ => daemon_json,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_collab() -> Value {
        json!({
            "id": "c-berry",
            "org_id": "org-secret",
            "name": "BerrySure",
            "instructions": "Ship the alpha.",
            "encryption_mode": "e2e",
            "memory_thread_id": "mem-1",
            "card_count": 1,
            "steerers": [{"user_id": "u1", "handle": "Alice@Acme"}],
            "roster": [{"address": "Alice@Acme/ChatGPT", "transport": "mcp", "agent_id": "a1"}],
            "lists": [{"id": "backlog", "name": "Backlog", "position": 0}],
            "cards": [{
                "id": "t-card",
                "last_subject": "Landing copy",
                "lane_id": "backlog",
                "status": "open",
                "from": "Alice@Acme",
                "audience": "Alice@Acme/chatgpt"
            }],
            "artifacts": [
                {"kind": "link", "label": "Staging", "url": "https://staging.example.com"},
                {
                    "kind": "file",
                    "name": "brief.md",
                    "path": "/tmp/brief.md",
                    "content": "secret-body",
                    "envelope": {"version": 1}
                }
            ],
            "learnings": [{
                "id": "l1",
                "created_at": "2026-08-16T00:00:00Z",
                "from_handle": "Alice@Acme",
                "notes": "Prefer bronze."
            }]
        })
    }

    #[test]
    fn get_collab_view_is_participant_complete() {
        let view = present_collab(&sample_collab());
        assert_eq!(view["id"], "c-berry");
        assert_eq!(view["name"], "BerrySure");
        assert_eq!(view["status"], "open");
        assert_eq!(view["instructions"], "Ship the alpha.");
        assert_eq!(view["people"][0]["handle"], "alice@acme");
        assert_eq!(view["agents"][0]["address"], "alice@acme/chatgpt");
        assert_eq!(view["cards"][0]["thread_id"], "t-card");
        assert_eq!(view["cards"][0]["subject"], "Landing copy");
        assert_eq!(view["artifacts"][0]["kind"], "link");
        assert_eq!(view["artifacts"][0]["url"], "https://staging.example.com");
        assert_eq!(view["artifacts"][1]["kind"], "file");
        assert_eq!(view["artifacts"][1]["path"], "/tmp/brief.md");
        assert!(view["artifacts"][1].get("envelope").is_none());
        assert!(view["artifacts"][1].get("content").is_none());
        assert!(view.get("org_id").is_none());
        assert!(view.get("steerers").is_none());
    }

    #[test]
    fn present_tool_result_wraps_list_and_get() {
        let listed = present_tool_result(
            "list_collabs",
            json!({ "collabs": [sample_collab()], "portfolio": {"totals": {}} }),
        );
        assert_eq!(listed["collabs"][0]["name"], "BerrySure");
        assert_eq!(listed["collabs"][0]["status"], "open");
        assert!(listed.get("portfolio").is_none());

        let mut archived = sample_collab();
        archived["status"] = json!("archived");
        let filtered = present_tool_result(
            "list_collabs",
            json!({ "collabs": [sample_collab(), archived] }),
        );
        assert_eq!(filtered["collabs"].as_array().map(|a| a.len()), Some(1));
        assert_eq!(filtered["collabs"][0]["name"], "BerrySure");

        let got = present_tool_result("get_collab", json!({ "collab": sample_collab() }));
        assert_eq!(got["collab"]["cards"][0]["thread_id"], "t-card");
    }
}
