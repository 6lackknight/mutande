//! Install the mutande agent skill into Cursor / ChatGPT / Claude Code paths,
//! and stage a Claude Desktop ZIP.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use zip::write::SimpleFileOptions;
use zip::CompressionMethod;
use zip::ZipWriter;

use super::connect_host::Host;
use super::user_home_dir;

/// Bundled skill body (repo `skill/SKILL.md`).
const SKILL_MD: &str = include_str!("../../../skill/SKILL.md");

const CLAUDE_CODE_HINT: &str = "Claude Code will load this on the next chat. Claude Desktop still needs the ZIP — Customize → Skills → Upload, then enable code execution under Capabilities.";

const CLAUDE_DESKTOP_HINT: &str = "Claude Desktop keeps skills in your account. Save the ZIP, then in Claude open Customize → Skills → Upload, turn the skill on, and enable code execution under Capabilities.";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SkillInstallMode {
    Auto,
    Manual,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstallSkillResult {
    pub host: String,
    pub ok: bool,
    pub mode: SkillInstallMode,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub zip_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hint: Option<String>,
}

/// Install (or stage) the mutande skill for one host.
pub fn install_skill(host: &str, home_override: Option<&Path>) -> Result<InstallSkillResult> {
    let home = match home_override {
        Some(h) => h.to_path_buf(),
        None => user_home_dir().context("could not resolve home directory")?,
    };
    let h = Host::parse(host)?;
    match h {
        Host::Cursor => install_auto(
            h,
            &[home.join(".cursor/skills/mutande/SKILL.md")],
            "Reload Cursor (or start a new agent chat) so it picks up the mutande skill.",
        ),
        Host::Chatgpt => install_auto(
            h,
            &[
                home.join(".agents/skills/mutande/SKILL.md"),
                home.join(".codex/skills/mutande/SKILL.md"),
            ],
            "Restart ChatGPT Desktop (or open a new chat) so it picks up the mutande skill.",
        ),
        Host::Claude => install_claude(&home),
    }
}

fn install_auto(host: Host, paths: &[PathBuf], hint: &str) -> Result<InstallSkillResult> {
    let mut written = Vec::new();
    let mut last_err: Option<String> = None;
    for path in paths {
        match write_skill_file(path) {
            Ok(()) => written.push(path.display().to_string()),
            Err(e) => last_err = Some(format!("{e:#}")),
        }
    }
    if written.is_empty() {
        return Ok(InstallSkillResult {
            host: host.as_str().into(),
            ok: false,
            mode: SkillInstallMode::Auto,
            path: paths.first().map(|p| p.display().to_string()),
            zip_path: None,
            hint: Some(last_err.unwrap_or_else(|| {
                "Couldn't write the skill file. Check folder permissions, then Retry.".into()
            })),
        });
    }
    Ok(InstallSkillResult {
        host: host.as_str().into(),
        ok: true,
        mode: SkillInstallMode::Auto,
        path: Some(written.join("; ")),
        zip_path: None,
        hint: Some(hint.into()),
    })
}

fn write_skill_file(path: &Path) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
    }
    fs::write(path, SKILL_MD).with_context(|| format!("write {}", path.display()))?;
    Ok(())
}

fn install_claude(home: &Path) -> Result<InstallSkillResult> {
    let code_path = home.join(".claude/skills/mutande/SKILL.md");
    let code_ok = write_skill_file(&code_path).is_ok();

    let dir = home.join(".mutande/skills");
    fs::create_dir_all(&dir).with_context(|| format!("create {}", dir.display()))?;
    let zip_path = dir.join("mutande-claude.zip");
    write_claude_skill_zip(&zip_path)?;
    let zip = zip_path.display().to_string();

    if code_ok {
        return Ok(InstallSkillResult {
            host: "claude".into(),
            ok: true,
            mode: SkillInstallMode::Auto,
            path: Some(code_path.display().to_string()),
            zip_path: Some(zip),
            hint: Some(CLAUDE_CODE_HINT.into()),
        });
    }
    Ok(InstallSkillResult {
        host: "claude".into(),
        ok: false,
        mode: SkillInstallMode::Manual,
        path: Some(code_path.display().to_string()),
        zip_path: Some(zip),
        hint: Some(CLAUDE_DESKTOP_HINT.into()),
    })
}

fn write_claude_skill_zip(zip_path: &Path) -> Result<()> {
    let file = fs::File::create(zip_path)
        .with_context(|| format!("create {}", zip_path.display()))?;
    let mut zip = ZipWriter::new(file);
    let opts = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);
    zip.start_file("mutande/SKILL.md", opts)?;
    zip.write_all(SKILL_MD.as_bytes())?;
    zip.finish()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    use zip::ZipArchive;

    #[test]
    fn cursor_writes_skill_md() {
        let dir = tempdir().unwrap();
        let home = dir.path();
        let r = install_skill("cursor", Some(home)).unwrap();
        assert!(r.ok);
        assert_eq!(r.mode, SkillInstallMode::Auto);
        let path = home.join(".cursor/skills/mutande/SKILL.md");
        assert!(path.exists());
        let body = fs::read_to_string(&path).unwrap();
        assert!(body.contains("name: mutande"));
        assert!(body.contains("Inbox on new chat"));
    }

    #[test]
    fn chatgpt_writes_both_skill_paths() {
        let dir = tempdir().unwrap();
        let home = dir.path();
        let r = install_skill("chatgpt", Some(home)).unwrap();
        assert!(r.ok);
        assert!(home.join(".agents/skills/mutande/SKILL.md").exists());
        assert!(home.join(".codex/skills/mutande/SKILL.md").exists());
    }

    #[test]
    fn claude_writes_code_skill_and_stages_zip() {
        let dir = tempdir().unwrap();
        let home = dir.path();
        let r = install_skill("claude", Some(home)).unwrap();
        assert!(r.ok);
        assert_eq!(r.mode, SkillInstallMode::Auto);
        let code = home.join(".claude/skills/mutande/SKILL.md");
        assert!(code.exists());
        assert!(fs::read_to_string(&code).unwrap().contains("name: mutande"));
        let zip_path = PathBuf::from(r.zip_path.as_ref().unwrap());
        assert!(zip_path.exists());
        let f = fs::File::open(&zip_path).unwrap();
        let mut archive = ZipArchive::new(f).unwrap();
        assert_eq!(archive.len(), 1);
        let mut file = archive.by_index(0).unwrap();
        assert_eq!(file.name(), "mutande/SKILL.md");
        let mut body = String::new();
        std::io::Read::read_to_string(&mut file, &mut body).unwrap();
        assert!(body.contains("name: mutande"));
        // Claude.ai description limit
        let desc = body
            .lines()
            .find(|l| l.starts_with("description:"))
            .unwrap();
        let desc_val = desc.trim_start_matches("description:").trim();
        assert!(desc_val.chars().count() <= 200, "desc too long: {}", desc_val.len());
        assert!(r.hint.as_ref().unwrap().contains("Claude Code"));
        assert!(r.hint.as_ref().unwrap().contains("Customize → Skills"));
    }

    #[test]
    fn invalid_host_rejected() {
        let err = install_skill("vscode", Some(Path::new("/tmp"))).unwrap_err();
        assert!(err.to_string().contains("invalid host"));
    }
}
