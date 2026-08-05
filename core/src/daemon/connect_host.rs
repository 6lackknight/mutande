//! Write MCP host configs so Cursor / Claude Desktop / ChatGPT point at `mutande-core mcp`.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use super::config::load_config;
use super::{expand_path, user_home_dir};

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

    pub fn parse(s: &str) -> Result<Self> {
        match s {
            "cursor" => Ok(Host::Cursor),
            "claude" => Ok(Host::Claude),
            "chatgpt" => Ok(Host::Chatgpt),
            other => bail!("invalid host: {other} (expected cursor|claude|chatgpt|all)"),
        }
    }

    fn restart_hint(self) -> &'static str {
        match self {
            Host::Cursor => {
                "Reload MCP in Cursor (or restart Cursor) so it loads the new MCP config."
            }
            Host::Claude => {
                "Quit and reopen Claude Desktop so it loads the new MCP config."
            }
            Host::Chatgpt => {
                "Quit and reopen ChatGPT Desktop so it loads the new MCP config."
            }
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct HostWriteResult {
    pub host: String,
    pub path: String,
    pub ok: bool,
    /// Absolute path written into the host MCP `command` field.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ConnectHostResult {
    pub command: String,
    pub args: Vec<String>,
    pub hosts: Vec<HostWriteResult>,
}

/// Stable install location: `~/.mutande/bin/mutande-core` (never Debug.app Resources).
pub fn stable_bin_path(home: &Path) -> PathBuf {
    #[cfg(windows)]
    {
        home.join(".mutande/bin/mutande-core.exe")
    }
    #[cfg(not(windows))]
    {
        home.join(".mutande/bin/mutande-core")
    }
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
    #[cfg(windows)]
    let output = Command::new("where")
        .arg("mutande-core.exe")
        .output()
        .or_else(|_| Command::new("where").arg("mutande-core").output())
        .ok()?;
    #[cfg(not(windows))]
    let output = Command::new("which")
        .arg("mutande-core")
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let path = String::from_utf8_lossy(&output.stdout)
        .lines()
        .next()
        .unwrap_or("")
        .trim()
        .to_string();
    if path.is_empty() {
        None
    } else {
        Some(path)
    }
}

fn looks_like_mutande_core(path: &Path) -> bool {
    path.file_name()
        .and_then(|s| s.to_str())
        .map(|n| n.starts_with("mutande-core"))
        .unwrap_or(false)
}

/// Prefer the running daemon binary, then resolved path on disk.
pub fn source_binary_path() -> Result<PathBuf> {
    if let Ok(exe) = std::env::current_exe() {
        if looks_like_mutande_core(&exe) && exe.is_file() {
            return Ok(exe);
        }
    }
    let resolved = resolve_mutande_core_command();
    let path = PathBuf::from(&resolved);
    if path.is_file() {
        return Ok(path);
    }
    bail!(
        "could not find mutande-core binary to install for MCP \
         (resolved '{resolved}'). Build core or set MUTANDE_CORE_PATH."
    );
}

/// Spawn `bin --help` and require exit 0 (catches Bad CPU type / missing binary).
pub fn preflight_mutande_core(bin: &Path) -> Result<()> {
    if !bin.is_file() {
        bail!("mutande-core not found at {}", bin.display());
    }
    let output = Command::new(bin)
        .arg("--help")
        .output()
        .with_context(|| {
            format!(
                "failed to spawn {} (wrong architecture or not executable)",
                bin.display()
            )
        })?;
    if output.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    bail!(
        "mutande-core preflight failed at {}{}",
        bin.display(),
        if stderr.is_empty() {
            String::new()
        } else {
            format!(": {stderr}")
        }
    );
}

/// Copy a native `mutande-core` into `~/.mutande/bin` and preflight it.
pub fn install_stable_mutande_core(home: &Path) -> Result<String> {
    let dest = stable_bin_path(home);
    let src = source_binary_path()?;

    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("create {}", parent.display()))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(parent, fs::Permissions::from_mode(0o700));
        }
    }

    let same = src
        .canonicalize()
        .ok()
        .zip(dest.canonicalize().ok())
        .map(|(a, b)| a == b)
        .unwrap_or(false);
    if !same {
        let tmp = dest.with_extension("new");
        fs::copy(&src, &tmp).with_context(|| {
            format!("copy {} → {}", src.display(), tmp.display())
        })?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&tmp, fs::Permissions::from_mode(0o755)).with_context(
                || format!("chmod {}", tmp.display()),
            )?;
        }
        fs::rename(&tmp, &dest).with_context(|| {
            format!("install {} → {}", src.display(), dest.display())
        })?;
    }

    preflight_mutande_core(&dest)?;
    Ok(dest.display().to_string())
}

fn merge_host_note(host: Host, extra: Option<String>) -> Option<String> {
    let restart = host.restart_hint();
    match (host == Host::Chatgpt, extra) {
        (true, Some(e)) => Some(format!("{}\n{}", CHATGPT_PATH_NOTE, e)),
        (true, None) => Some(format!("{}\n{}", CHATGPT_PATH_NOTE, restart)),
        (false, Some(e)) => Some(format!("{e}\n{restart}")),
        (false, None) => Some(restart.to_string()),
    }
}

/// Config path relative to `home` (tests inject a temp home).
pub fn config_path_for_host(host: Host, home: &Path) -> PathBuf {
    match host {
        Host::Cursor => home.join(".cursor/mcp.json"),
        Host::Claude => {
            if cfg!(windows) {
                home.join("AppData/Roaming/Claude/claude_desktop_config.json")
            } else {
                home.join("Library/Application Support/Claude/claude_desktop_config.json")
            }
        }
        Host::Chatgpt => {
            if cfg!(windows) {
                home.join("AppData/Roaming/ChatGPT/mcp.json")
            } else {
                home.join("Library/Application Support/ChatGPT/mcp.json")
            }
        }
    }
}

pub fn mcp_server_name(host: Host) -> &'static str {
    match host {
        Host::Cursor => "mutande-cursor",
        Host::Claude => "mutande-claude",
        Host::Chatgpt => "mutande-chatgpt",
    }
}

pub fn mcp_server_entry(command: &str, agent_slug: &str) -> Value {
    serde_json::json!({
        "command": command,
        "args": ["mcp"],
        "env": {
            "MUTANDE_AGENT_SLUG": agent_slug
        }
    })
}

/// Merge-write the mutande MCP server into an existing host config (or create it).
pub fn merge_write_mcp_config(path: &Path, command: &str, host: Host) -> Result<()> {
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
    servers.insert(
        mcp_server_name(host).to_string(),
        mcp_server_entry(command, host.as_str()),
    );

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
    }
    let pretty = serde_json::to_string_pretty(&root)?;
    fs::write(path, pretty + "\n").with_context(|| format!("write {}", path.display()))?;
    Ok(())
}

/// Connect one or all hosts. `home_override` / `command_override` are for tests;
/// production installs a stable binary under `~/.mutande/bin` then writes configs.
pub fn connect_host(host: &str, home_override: Option<&Path>) -> Result<ConnectHostResult> {
    connect_host_inner(host, home_override, None)
}

fn connect_host_inner(
    host: &str,
    home_override: Option<&Path>,
    command_override: Option<&str>,
) -> Result<ConnectHostResult> {
    let home = match home_override {
        Some(h) => h.to_path_buf(),
        None => user_home_dir().context("could not resolve home directory")?,
    };

    let command = match command_override {
        Some(c) => c.to_string(),
        None => install_stable_mutande_core(&home)?,
    };

    let targets: Vec<Host> = if host == "all" {
        vec![Host::Cursor, Host::Claude, Host::Chatgpt]
    } else {
        vec![Host::parse(host)?]
    };

    let mut hosts = Vec::with_capacity(targets.len());
    for h in targets {
        let path = config_path_for_host(h, &home);
        match merge_write_mcp_config(&path, &command, h) {
            Ok(()) => hosts.push(HostWriteResult {
                host: h.as_str().into(),
                path: path.display().to_string(),
                ok: true,
                command: Some(command.clone()),
                note: merge_host_note(h, None),
            }),
            Err(err) => hosts.push(HostWriteResult {
                host: h.as_str().into(),
                path: path.display().to_string(),
                ok: false,
                command: Some(command.clone()),
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
    use std::os::unix::fs::PermissionsExt;
    use tempfile::tempdir;

    fn write_fake_help_bin(path: &Path) {
        fs::write(
            path,
            "#!/bin/sh\nif [ \"$1\" = \"--help\" ]; then exit 0; fi\nexit 1\n",
        )
        .unwrap();
        fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
    }

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

        merge_write_mcp_config(&path, "/opt/mutande-core", Host::Cursor).unwrap();

        let data: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(
            data["mcpServers"]["mutande-cursor"]["command"],
            "/opt/mutande-core"
        );
        assert_eq!(data["mcpServers"]["mutande-cursor"]["args"][0], "mcp");
        assert_eq!(
            data["mcpServers"]["mutande-cursor"]["env"]["MUTANDE_AGENT_SLUG"],
            "cursor"
        );
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
        for h in &result.hosts {
            assert!(
                h.ok,
                "expected ok for {}: note={:?}",
                h.host, h.note
            );
        }
        assert!(result
            .hosts
            .iter()
            .all(|h| h.command.as_deref() == Some("/tmp/fake-mutande-core")));
        assert!(result
            .hosts
            .iter()
            .find(|h| h.host == "claude")
            .and_then(|h| h.note.as_ref())
            .is_some_and(|n| n.contains("Quit and reopen Claude Desktop")));

        let cursor = home.join(".cursor/mcp.json");
        let claude = home.join("Library/Application Support/Claude/claude_desktop_config.json");
        let chatgpt = home.join("Library/Application Support/ChatGPT/mcp.json");
        assert!(cursor.exists());
        assert!(claude.exists());
        assert!(chatgpt.exists());

        let written: Value =
            serde_json::from_str(&fs::read_to_string(&cursor).unwrap()).unwrap();
        assert_eq!(
            written["mcpServers"]["mutande-cursor"]["command"],
            "/tmp/fake-mutande-core"
        );

        let chatgpt_note = result
            .hosts
            .iter()
            .find(|h| h.host == "chatgpt")
            .and_then(|h| h.note.as_ref());
        assert!(chatgpt_note.is_some_and(|n| n.contains("ChatGPT path")));
    }

    #[test]
    fn install_stable_copies_and_prefights() {
        let dir = tempdir().unwrap();
        let home = dir.path();
        let src = home.join("src-bin");
        write_fake_help_bin(&src);

        let dest = install_stable_mutande_core_from(home, &src).unwrap();
        assert!(Path::new(&dest).exists());
        assert_eq!(Path::new(&dest), stable_bin_path(home));
        preflight_mutande_core(Path::new(&dest)).unwrap();
    }

    #[test]
    fn preflight_rejects_missing_binary() {
        let err = preflight_mutande_core(Path::new("/no/such/mutande-core")).unwrap_err();
        assert!(err.to_string().contains("not found"));
    }

    /// Test helper: install from an explicit source (avoids depending on current_exe).
    fn install_stable_mutande_core_from(home: &Path, src: &Path) -> Result<String> {
        let dest = stable_bin_path(home);
        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent)?;
        }
        let tmp = dest.with_extension("new");
        fs::copy(src, &tmp)?;
        fs::set_permissions(&tmp, fs::Permissions::from_mode(0o755))?;
        fs::rename(&tmp, &dest)?;
        preflight_mutande_core(&dest)?;
        Ok(dest.display().to_string())
    }

    #[test]
    fn invalid_host_rejected() {
        let err = connect_host("vscode", Some(Path::new("/tmp"))).unwrap_err();
        assert!(err.to_string().contains("invalid host"));
    }
}
