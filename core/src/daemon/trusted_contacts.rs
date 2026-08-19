//! Pre-trusted org contacts — skip task gate after verify_contact / explicit trust.

use std::collections::BTreeSet;
use std::fs;
use std::path::PathBuf;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use super::expand_path;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct TrustedFile {
    #[serde(default)]
    handles: BTreeSet<String>,
}

pub struct TrustedContacts {
    path: PathBuf,
    data: TrustedFile,
}

impl TrustedContacts {
    pub fn load_default() -> Self {
        Self::load(expand_path("~/.mutande/trusted_contacts.json"))
    }

    pub fn load(path: PathBuf) -> Self {
        let data = fs::read_to_string(&path)
            .ok()
            .and_then(|raw| serde_json::from_str(&raw).ok())
            .unwrap_or_default();
        Self { path, data }
    }

    pub fn is_trusted(&self, handle: &str) -> bool {
        let bare = normalize_handle(handle);
        self.data.handles.contains(&bare)
    }

    pub fn trust(&mut self, handle: &str) -> Result<()> {
        self.data.handles.insert(normalize_handle(handle));
        self.save()
    }

    #[allow(dead_code)]
    pub fn untrust(&mut self, handle: &str) -> Result<()> {
        self.data.handles.remove(&normalize_handle(handle));
        self.save()
    }

    fn save(&self) -> Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("create {}", parent.display()))?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = fs::set_permissions(parent, fs::Permissions::from_mode(0o700));
            }
        }
        let json = serde_json::to_string_pretty(&self.data)?;
        fs::write(&self.path, &json).with_context(|| format!("write {}", self.path.display()))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&self.path, fs::Permissions::from_mode(0o600));
        }
        Ok(())
    }
}

fn normalize_handle(handle: &str) -> String {
    let h = handle.trim().to_ascii_lowercase();
    if let Some((bare, _)) = h.rsplit_once('/') {
        bare.to_string()
    } else {
        h
    }
}
