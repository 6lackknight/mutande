//! Intro-card sanitizer for `publish_handshake`. Names only — no secrets/paths.

use crate::hub_client::HandshakeCard;

const MAX_LIST: usize = 12;
const MAX_ITEM: usize = 80;
const MAX_HOST: usize = 40;
const MAX_ADDRESS: usize = 120;
const MAX_FORMAT: usize = 80;

pub fn looks_secret_or_path(raw: &str) -> bool {
    let t = raw.trim();
    if t.is_empty() {
        return false;
    }
    let lower = t.to_ascii_lowercase();
    if lower.starts_with("sk-")
        || lower.starts_with("sk_live")
        || lower.starts_with("sk_test")
        || lower.starts_with("ghp_")
        || lower.starts_with("github_pat_")
        || lower.starts_with("xox")
    {
        return true;
    }
    if lower.contains("api_key=")
        || lower.contains("api-key=")
        || lower.contains("secret=")
        || lower.contains("token=")
        || lower.contains("password=")
        || lower.contains("bearer ")
    {
        return true;
    }
    t.starts_with("/Users/")
        || t.starts_with("/home/")
        || t.starts_with("~/")
        || t.starts_with("file://")
        || (t.len() >= 3 && t.as_bytes()[1] == b':' && t.as_bytes()[2] == b'\\')
}

fn clip_item(raw: &str, max: usize) -> Option<String> {
    let t = raw.split_whitespace().collect::<Vec<_>>().join(" ");
    if t.is_empty() || looks_secret_or_path(&t) {
        return None;
    }
    if t.chars().count() > max {
        Some(t.chars().take(max).collect())
    } else {
        Some(t)
    }
}

fn clip_list(items: &[String], max_item: usize) -> Vec<String> {
    let mut out = Vec::new();
    let mut seen = std::collections::BTreeSet::new();
    for item in items {
        let Some(v) = clip_item(item, max_item) else {
            continue;
        };
        let key = v.to_ascii_lowercase();
        if !seen.insert(key) {
            continue;
        }
        out.push(v);
        if out.len() >= MAX_LIST {
            break;
        }
    }
    out
}

pub fn host_display_name(slug: &str) -> &'static str {
    match slug.trim().to_ascii_lowercase().as_str() {
        "cursor" => "Cursor",
        "claude" => "Claude",
        "chatgpt" | "chatgpt-web" => "ChatGPT",
        "claude-web" => "Claude",
        other if other.contains("chatgpt") => "ChatGPT",
        other if other.contains("claude") => "Claude",
        _ => "AI host",
    }
}

pub fn sanitize_handshake(card: HandshakeCard) -> HandshakeCard {
    HandshakeCard {
        host: card.host.as_deref().and_then(|s| clip_item(s, MAX_HOST)),
        address: card.address.as_deref().and_then(|s| clip_item(s, MAX_ADDRESS)),
        models: clip_list(&card.models, MAX_ITEM),
        skills: clip_list(&card.skills, MAX_ITEM),
        ask_me_about: clip_list(&card.ask_me_about, MAX_ITEM),
        preferred_file_format: card
            .preferred_file_format
            .as_deref()
            .and_then(|s| clip_item(s, MAX_FORMAT)),
        other_tools: clip_list(&card.other_tools, MAX_ITEM),
        published_at: card.published_at,
    }
}

pub fn handshake_notes(card: &HandshakeCard) -> String {
    let mut lines = vec!["Handshake".to_string()];
    if let Some(h) = &card.host {
        lines.push(format!("Host: {h}"));
    }
    if let Some(a) = &card.address {
        lines.push(format!("Address: {a}"));
    }
    if !card.models.is_empty() {
        lines.push(format!("Models: {}", card.models.join(", ")));
    }
    if !card.skills.is_empty() {
        lines.push(format!("Skills: {}", card.skills.join(", ")));
    }
    if !card.ask_me_about.is_empty() {
        lines.push(format!("Ask me about: {}", card.ask_me_about.join(", ")));
    }
    if let Some(f) = &card.preferred_file_format {
        lines.push(format!("Preferred files: {f}"));
    }
    if !card.other_tools.is_empty() {
        lines.push(format!("Other tools: {}", card.other_tools.join(", ")));
    }
    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_secrets_and_paths() {
        let card = sanitize_handshake(HandshakeCard {
            host: Some("Cursor".into()),
            models: vec!["Composer".into(), "sk-live-secret".into(), "~/keys".into()],
            other_tools: vec!["github".into(), "Bearer abc.def".into()],
            ask_me_about: vec!["routing".into(), "api_key=foo".into()],
            preferred_file_format: Some("markdown".into()),
            ..Default::default()
        });
        assert_eq!(card.host.as_deref(), Some("Cursor"));
        assert_eq!(card.models, vec!["Composer"]);
        assert_eq!(card.other_tools, vec!["github"]);
        assert_eq!(card.ask_me_about, vec!["routing"]);
    }
}
