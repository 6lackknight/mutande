# macOS updates (Sparkle) — v1 stub

## Status

**Deferred for v1 plumbing.** Auto-updates via Sparkle + notarization are a
PRD requirement (story 37) but not wired in this branch.

## Intended path

1. Sign and notarize `Mutande.app` (Developer ID).
2. Embed [Sparkle](https://sparkle-project.org/) in the Flutter macOS Runner
   (native Swift/`AppDelegate` or a thin plugin).
3. Host an `appcast.xml` (GitHub Releases or CDN) with EdDSA signatures.
4. Menu: **Check for Updates…** on the tray / Session tab.

## Until then

- Ship security fixes by redistributing a new `.dmg` / `.app` zip.
- `mutande-core` is bundled as a sidecar in `Contents/Resources/mutande-core`
  (see `app/macos/Runner/Scripts/bundle_mutande_core.sh`); bump both app and
  core together.
- Document release version in `app/pubspec.yaml` (`version:`) and
  `core/Cargo.toml`.

## Explicit remaining gap

Sparkle integration, notarization pipeline, and update UX are **out of this
plumbing PR** and tracked as a follow-up before public beta.
