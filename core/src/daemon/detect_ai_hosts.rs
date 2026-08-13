//! Probe whether AI host desktop apps and MCP config paths exist on this machine.

use std::path::{Path, PathBuf};

use serde::Serialize;

use super::connect_host::{config_path_for_host, Host};

#[derive(Debug, Clone, Serialize)]
pub struct HostDetection {
    pub host: String,
    /// True when the host's desktop `.app` / install is found — not inferred from config alone.
    pub installed: bool,
    /// Known MCP config path exists (informational; does not imply installed).
    pub config_present: bool,
}

fn app_bundle_paths(home: &Path, app_name: &str) -> [PathBuf; 2] {
    [
        PathBuf::from(format!("/Applications/{app_name}.app")),
        home.join(format!("Applications/{app_name}.app")),
    ]
}

fn app_installed(home: &Path, app_name: &str) -> bool {
    app_bundle_paths(home, app_name)
        .into_iter()
        .any(|p| p.is_dir())
}

pub fn detect_for_home(home: &Path) -> Vec<HostDetection> {
    let hosts = [Host::Cursor, Host::Claude, Host::Chatgpt];
    hosts
        .into_iter()
        .map(|h| {
            let app_name = match h {
                Host::Cursor => "Cursor",
                Host::Claude => "Claude",
                Host::Chatgpt => "ChatGPT",
            };
            let config = config_path_for_host(h, home);
            HostDetection {
                host: h.as_str().to_string(),
                installed: app_installed(home, app_name),
                config_present: config.is_file(),
            }
        })
        .collect()
}

pub fn detect() -> Vec<HostDetection> {
    let home = super::user_home_dir().unwrap_or_else(|| PathBuf::from("."));
    detect_for_home(&home)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn config_alone_does_not_mark_installed() {
        let tmp = tempfile::tempdir().unwrap();
        let home = tmp.path();
        let cursor_cfg = config_path_for_host(Host::Cursor, home);
        fs::create_dir_all(cursor_cfg.parent().unwrap()).unwrap();
        fs::write(&cursor_cfg, "{}").unwrap();

        let d = detect_for_home(home)
            .into_iter()
            .find(|h| h.host == "cursor")
            .unwrap();
        assert!(!d.installed);
        assert!(d.config_present);
    }

    #[test]
    fn app_bundle_marks_installed() {
        let tmp = tempfile::tempdir().unwrap();
        let home = tmp.path();
        fs::create_dir_all(home.join("Applications/Cursor.app")).unwrap();

        let d = detect_for_home(home)
            .into_iter()
            .find(|h| h.host == "cursor")
            .unwrap();
        assert!(d.installed);
    }
}
