//! Display ↔ wire address transforms for agent-scoped handles.

use std::collections::HashSet;
use std::sync::LazyLock;

use anyhow::{Context, Result, bail};

static RESERVED: LazyLock<HashSet<&'static str>> =
    LazyLock::new(|| HashSet::from(["default", "all"]));

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AddressKind {
    User,
    OrgBroadcast,
    SelfAgent,
    MyAgents,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ParsedDisplayAddress {
    pub kind: AddressKind,
    pub local: String,
    pub org_slug: String,
    pub agent_slug: Option<String>,
}

/// Org-wide broadcast: `@all@org`.
pub fn is_broadcast_handle(handle: &str) -> bool {
    handle.starts_with("@all@")
}

/// Shared my-agents group: bare `@all`.
pub fn is_my_agents_handle(handle: &str) -> bool {
    handle.trim() == "@all"
}

pub fn broadcast_handle(org_slug: &str) -> String {
    format!("@all@{org_slug}")
}

pub fn my_agents_handle() -> &'static str {
    "@all"
}

fn is_valid_agent_slug(slug: &str) -> bool {
    if slug.is_empty() || slug.len() > 32 {
        return false;
    }
    slug.bytes()
        .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

pub fn assert_valid_agent_slug(slug: &str) -> Result<()> {
    if !is_valid_agent_slug(slug) {
        bail!("invalid agent slug: must be 1–32 lowercase letters, digits, or hyphens");
    }
    if RESERVED.contains(slug) {
        bail!("agent slug '{slug}' is reserved");
    }
    Ok(())
}

/// Parse `alice@acme`, `alice@acme/claude`, `@all@acme`, bare `@all`, or `@claude`.
pub fn parse_display_address(input: &str) -> Result<ParsedDisplayAddress> {
    let trimmed = input.trim();

    if is_my_agents_handle(trimmed) {
        return Ok(ParsedDisplayAddress {
            kind: AddressKind::MyAgents,
            local: "@all".into(),
            org_slug: String::new(),
            agent_slug: None,
        });
    }

    if is_broadcast_handle(trimmed) {
        let org_slug = trimmed.strip_prefix("@all@").unwrap_or("");
        if org_slug.is_empty() {
            bail!("invalid broadcast handle");
        }
        return Ok(ParsedDisplayAddress {
            kind: AddressKind::OrgBroadcast,
            local: "@all".into(),
            org_slug: org_slug.into(),
            agent_slug: None,
        });
    }

    // Self-agent shorthand: `@claude` (single leading @, no other @ or /).
    if trimmed.starts_with('@')
        && !trimmed[1..].contains('/')
        && !trimmed[1..].contains('@')
    {
        let slug = &trimmed[1..];
        if slug.is_empty() {
            bail!("invalid handle format");
        }
        assert_valid_agent_slug(slug)?;
        return Ok(ParsedDisplayAddress {
            kind: AddressKind::SelfAgent,
            local: String::new(),
            org_slug: String::new(),
            agent_slug: Some(slug.to_string()),
        });
    }

    let (base, agent_slug) = match trimmed.split_once('/') {
        Some((b, slug)) => {
            if slug.is_empty() {
                bail!("missing agent slug after /");
            }
            assert_valid_agent_slug(slug)?;
            (b, Some(slug.to_string()))
        }
        None => (trimmed, None),
    };

    let at = base.rfind('@').context("invalid handle format")?;
    if at == 0 || at == base.len() - 1 {
        bail!("invalid handle format");
    }
    let local = base[..at].to_string();
    let org_slug = base[at + 1..].to_string();
    if local.eq_ignore_ascii_case("@all") || local.to_ascii_lowercase().starts_with("@all") {
        bail!("handle cannot use @all broadcast prefix");
    }

    Ok(ParsedDisplayAddress {
        kind: AddressKind::User,
        local,
        org_slug,
        agent_slug,
    })
}

pub fn bare_handle(local: &str, org_slug: &str) -> String {
    format!("{local}@{org_slug}")
}

pub fn format_display_address(local: &str, org_slug: &str, agent_slug: Option<&str>) -> String {
    match agent_slug {
        Some(slug) => format!("{local}@{org_slug}/{slug}"),
        None => bare_handle(local, org_slug),
    }
}

pub fn strip_agent_suffix(display: &str) -> &str {
    display.split('/').next().unwrap_or(display)
}

pub fn agent_suffix(display: &str) -> Option<&str> {
    display.split_once('/').map(|(_, slug)| slug)
}

pub fn format_wire_path(org_slug: &str, local: &str, agent_slug: &str) -> String {
    format!("{org_slug}/{local}/{agent_slug}")
}

pub fn parse_wire_path(path: &str) -> Result<(String, String, String)> {
    let parts: Vec<&str> = path.split('/').collect();
    if parts.len() != 3 || parts.iter().any(|p| p.is_empty()) {
        bail!("invalid wire path (expected org/user/agent)");
    }
    assert_valid_agent_slug(parts[2])?;
    Ok((parts[0].into(), parts[1].into(), parts[2].into()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_and_format_roundtrip() {
        let p = parse_display_address("alice@acme/claude").unwrap();
        assert_eq!(p.kind, AddressKind::User);
        assert_eq!(p.local, "alice");
        assert_eq!(p.org_slug, "acme");
        assert_eq!(p.agent_slug.as_deref(), Some("claude"));
        assert_eq!(
            format_display_address(&p.local, &p.org_slug, p.agent_slug.as_deref()),
            "alice@acme/claude"
        );
        assert_eq!(format_wire_path("acme", "alice", "claude"), "acme/alice/claude");
    }

    #[test]
    fn parse_self_agent_shorthand() {
        let p = parse_display_address("@claude").unwrap();
        assert_eq!(p.kind, AddressKind::SelfAgent);
        assert_eq!(p.agent_slug.as_deref(), Some("claude"));
    }

    #[test]
    fn parse_my_agents_vs_org_broadcast() {
        let mine = parse_display_address("@all").unwrap();
        assert_eq!(mine.kind, AddressKind::MyAgents);
        let org = parse_display_address("@all@acme").unwrap();
        assert_eq!(org.kind, AddressKind::OrgBroadcast);
        assert_eq!(org.org_slug, "acme");
        assert!(is_my_agents_handle("@all"));
        assert!(!is_my_agents_handle("@all@acme"));
        assert!(is_broadcast_handle("@all@acme"));
        assert!(!is_broadcast_handle("@all"));
    }

    #[test]
    fn strip_suffix() {
        assert_eq!(strip_agent_suffix("bob@acme/research"), "bob@acme");
        assert_eq!(agent_suffix("bob@acme/research"), Some("research"));
    }

    #[test]
    fn reserved_slug_rejected() {
        assert!(parse_display_address("x@y/default").is_err());
        assert!(parse_display_address("@default").is_err());
        assert!(parse_display_address("@all").is_ok()); // my_agents, not slug
    }
}
