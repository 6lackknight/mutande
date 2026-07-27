//! Write MCP host configs so Cursor / Claude Desktop / ChatGPT point at `mutande-core mcp`.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use super::config::load_config;
use super::expand_path;

pub const SERVER_NAME: &str = "mutande";

/// ChatGPT desktop MCP path is not officially documented and has varied across
/// early builds. We write `~/Library/Application Support/ChatGPT/mcp.json`.
/// Also reported: `mcp_config.json`, `chatgpt_mcp_config.json` in the same dir.
pub const CHATGPT_PATH_NOTE: &str = "ChatGPT path unconfirmed; also seen: \
    ~/Library/Application Support/ChatGPT/mcp_config.json and chatgpt_mcp_config.json. \
    Prefer Settings → MCP if the file is ignored.";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Host {
    Cursor,
    Claude,
    Chatgpt,
}

impl Host {
    pub fn as_str(self) -> &'static str {
        match self {
            Host::Cursor => "cursor",
            Host::Claude => "claude",
            Host::Chatgpt => "chatgpt",
        }
    }

    fn parse(s: &str) -> Result<Self> {
        match s {
            "cursor" => Ok(Host::Cursor),
            "claude" => Ok(Host::Claude),
            "chatgpt" => Ok(Host::Chatgpt),
            other => bail!("invalid host: {other} (expected cursor|claude|chatgpt|all)"),
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct HostWriteResult {
    pub host: String,
    pub path: String,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ConnectHostResult {
    pub command: String,
    pub args: Vec<String>,
    pub hosts: Vec<HostWriteResult>,
}

/// Resolve the `mutande-core` binary for MCP configs.
///
/// Order: `MUTANDE_CORE_PATH` env → `~/.mutande/config.json` `mutande_core_path`
/// → `which mutande-core` → bare `mutande-core` (relies on host PATH).
pub fn resolve_mutande_core_command() -> String {
    if let Ok(p) = std::env::var("MUTANDE_CORE_PATH") {
        let p = p.trim();
        if !p.is_empty() {
            return p.to_string();
        }
    }

    if let Ok(cfg) = load_config() {
        if let Some(p) = cfg.mutande_core_path {
            let p = p.trim();
            if !p.is_empty() {
                return expand_path(p).to_string_lossy().into_owned();
            }
        }
    }

    if let Some(path) = which_mutande_core() {
        return path;
    }

    "mutande-core".to_string()
}

fn which_mutande_core() -> Option<String> {
    let output = Command::new("/usr/bin/which")
        .arg("mutande-core")
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if path.is_empty() {
        None
    } else {
        Some(path)
    }
}

/// Config path relative to `home` (tests inject a temp home).
pub fn config_path_for_host(host: Host, home: &Path) -> PathBuf {
    match host {
        Host::Cursor => home.join(".cursor/mcp.json"),
        Host::Claude => home
            .join("Library/Application Support/Claude/claude_desktop_config.json"),
        Host::Chatgpt => home.join("Library/Application Support/ChatGPT/mcp.json"),
    }
}

pub fn mcp_server_entry(command: &str) -> Value {
    serde_json::json!({
        "command": command,
        "args": ["mcp"],
    })
}

/// Merge-write the mutande MCP server into an existing host config (or create it).
pub fn merge_write_mcp_config(path: &Path, command: &str) -> Result<()> {
    let mut root: Value = if path.exists() {
        let data = fs::read_to_string(path)
            .with_context(|| format!("read {}", path.display()))?;
        if data.trim().is_empty() {
            Value::Object(Map::new())
        } else {
            serde_json::from_str(&data).with_context(|| {
                format!("parse existing MCP config {}", path.display())
            })?
        }
    } else {
        Value::Object(Map::new())
    };

    let obj = root.as_object_mut().context("MCP config root must be a JSON object")?;
    let servers = obj
        .entry("mcpServers")
        .or_insert_with(|| Value::Object(Map::new()));
    let servers = servers
        .as_object_mut()
        .context("mcpServers must be a JSON object")?;
    servers.insert(SERVER_NAME.to_string(), mcp_server_entry(command));

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
    }
    let pretty = serde_json::to_string_pretty(&root)?;
    fs::write(path, pretty + "\n").with_context(|| format!("write {}", path.display()))?;
    Ok(())
}

/// Connect one or all hosts. `home_override` / `command_override` are for tests;
/// production uses `dirs::home_dir()` and [`resolve_mutande_core_command`].
pub fn connect_host(host: &str, home_override: Option<&Path>) -> Result<ConnectHostResult> {
    connect_host_inner(host, home_override, None)
}

fn connect_host_inner(
    host: &str,
    home_override: Option<&Path>,
    command_override: Option<&str>,
) -> Result<ConnectHostResult> {
    let command = match command_override {
        Some(c) => c.to_string(),
        None => resolve_mutande_core_command(),
    };
    let home = match home_override {
        Some(h) => h.to_path_buf(),
        None => dirs::home_dir().context("could not resolve home directory")?,
    };

    let targets: Vec<Host> = if host == "all" {
        vec![Host::Cursor, Host::Claude, Host::Chatgpt]
    } else {
        vec![Host::parse(host)?]
    };

    let mut hosts = Vec::with_capacity(targets.len());
    for h in targets {
        let path = config_path_for_host(h, &home);
        let note = if h == Host::Chatgpt {
            Some(CHATGPT_PATH_NOTE.to_string())
        } else {
            None
        };
        match merge_write_mcp_config(&path, &command) {
            Ok(()) => hosts.push(HostWriteResult {
                host: h.as_str().into(),
                path: path.display().to_string(),
                ok: true,
                note,
            }),
            Err(err) => hosts.push(HostWriteResult {
                host: h.as_str().into(),
                path: path.display().to_string(),
                ok: false,
                note: Some(format!("{err:#}")),
            }),
        }
    }

    if hosts.iter().all(|h| !h.ok) {
        bail!("connect_host failed for all targets");
    }

    Ok(ConnectHostResult {
        command,
        args: vec!["mcp".into()],
        hosts,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn merge_creates_and_preserves_other_servers() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("mcp.json");
        fs::write(
            &path,
            r#"{
  "mcpServers": {
    "other": { "command": "echo", "args": ["hi"] }
  }
}
"#,
        )
        .unwrap();

        merge_write_mcp_config(&path, "/opt/mutande-core").unwrap();

        let data: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(data["mcpServers"]["mutande"]["command"], "/opt/mutande-core");
        assert_eq!(data["mcpServers"]["mutande"]["args"][0], "mcp");
        assert_eq!(data["mcpServers"]["other"]["command"], "echo");
    }

    #[test]
    fn connect_all_writes_under_temp_home() {
        let dir = tempdir().unwrap();
        let home = dir.path();

        let result =
            connect_host_inner("all", Some(home), Some("/tmp/fake-mutande-core")).unwrap();

        assert_eq!(result.command, "/tmp/fake-mutande-core");
        assert_eq!(result.hosts.len(), 3);
        assert!(result.hosts.iter().all(|h| h.ok));

        let cursor = home.join(".cursor/mcp.json");
        let claude = home.join("Library/Application Support/Claude/claude_desktop_config.json");
        let chatgpt = home.join("Library/Application Support/ChatGPT/mcp.json");
        assert!(cursor.exists());
        assert!(claude.exists());
        assert!(chatgpt.exists());

        let written: Value =
            serde_json::from_str(&fs::read_to_string(&cursor).unwrap()).unwrap();
        assert_eq!(
            written["mcpServers"]["mutande"]["command"],
            "/tmp/fake-mutande-core"
        );

        let chatgpt_note = result
            .hosts
            .iter()
            .find(|h| h.host == "chatgpt")
            .and_then(|h| h.note.as_ref());
        assert!(chatgpt_note.is_some());
    }

    #[test]
    fn invalid_host_rejected() {
        let err = connect_host("vscode", Some(Path::new("/tmp"))).unwrap_err();
        assert!(err.to_string().contains("invalid host"));
    }
}
