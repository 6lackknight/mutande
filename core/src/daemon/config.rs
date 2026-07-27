use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use rand::RngCore;
use serde::{Deserialize, Serialize};

use super::expand_path;

/// Write secret-bearing files atomically with mode `0o600` (create-time mode + harden).
/// Always restricts; callers only use this for tokens, config, and device keys.
#[cfg(unix)]
pub fn write_restricted_file(path: &Path, contents: impl AsRef<[u8]>) -> Result<()> {
    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
        fs::set_permissions(parent, fs::Permissions::from_mode(0o700))
            .with_context(|| format!("chmod dir {}", parent.display()))?;
    }

    // Create with 0o600 so the file is never briefly world-readable (write-then-chmod race).
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)
        .with_context(|| format!("open {}", path.display()))?;
    file.write_all(contents.as_ref())
        .with_context(|| format!("write {}", path.display()))?;
    file.sync_all()
        .with_context(|| format!("sync {}", path.display()))?;
    // Harden if the path already existed with looser permissions (mode applies on create only).
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))
        .with_context(|| format!("chmod {}", path.display()))?;
    Ok(())
}

#[cfg(not(unix))]
pub fn write_restricted_file(path: &Path, contents: impl AsRef<[u8]>) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
    }
    fs::write(path, contents.as_ref()).with_context(|| format!("write {}", path.display()))?;
    Ok(())
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct DaemonConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hub_url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub jwt: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub refresh_token: Option<String>,
    /// Absolute path to `mutande-core` for MCP host configs (`connect_host`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mutande_core_path: Option<String>,
}

pub fn config_path() -> PathBuf {
    expand_path("~/.mutande/config.json")
}

/// Path to the local HTTP bridge bearer token (`0o600`).
/// Flutter reads the same file (`DaemonClient`).
pub fn http_token_path() -> PathBuf {
    expand_path("~/.mutande/daemon_http_token")
}

/// Load existing HTTP token or generate one and write it restricted.
pub fn ensure_http_token() -> Result<String> {
    ensure_http_token_at(&http_token_path())
}

pub fn ensure_http_token_at(path: &Path) -> Result<String> {
    if path.exists() {
        let existing = fs::read_to_string(path)
            .with_context(|| format!("read {}", path.display()))?;
        let token = existing.trim().to_string();
        if !token.is_empty() {
            return Ok(token);
        }
    }

    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    let token = hex::encode(bytes);
    write_restricted_file(path, format!("{token}\n"))
        .with_context(|| format!("write {}", path.display()))?;
    Ok(token)
}

pub fn load_config() -> Result<DaemonConfig> {
    let path = config_path();
    if !path.exists() {
        return Ok(DaemonConfig::default());
    }
    let data = fs::read_to_string(&path).with_context(|| format!("read {}", path.display()))?;
    serde_json::from_str(&data).context("parse config.json")
}

pub fn save_config(config: &DaemonConfig) -> Result<()> {
    save_config_at(&config_path(), config)
}

pub fn save_config_at(path: &Path, config: &DaemonConfig) -> Result<()> {
    let data = serde_json::to_string_pretty(config)?;
    write_restricted_file(path, data).context("write config.json")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn write_restricted_file_always_0600() {
        let dir = tempfile::tempdir().unwrap();
        // Outside `.mutande` — must still harden (token/config/device paths).
        let path = dir.path().join("secret.bin");
        write_restricted_file(&path, b"secret").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(&path).unwrap().permissions();
            assert_eq!(mode.mode() & 0o777, 0o600);
            let parent = fs::metadata(dir.path()).unwrap().permissions();
            assert_eq!(parent.mode() & 0o777, 0o700);
        }
    }
}
