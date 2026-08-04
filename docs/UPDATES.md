# Desktop updates — v1 stub

## Status

**Mac:** DMG release script exists (`scripts/release-macos-dmg.sh`). Developer ID
signing + notarization via `mutande-notary` keychain profile. Sparkle
auto-updates remain deferred (PRD story 37).

**Windows:** Unsigned alpha zip via GitHub Actions
(`.github/workflows/release-windows.yml`). See `scripts/release-windows.md`.
SmartScreen warnings are expected; Authenticode deferred.

## Release (notarized DMG)

```bash
# One-time (Apple ID + app-specific password from appleid.apple.com):
xcrun notarytool store-credentials "mutande-notary" \
  --apple-id "you@example.com" \
  --team-id "Q22P2YXR6M" \
  --password "<app-specific-password>"

# Both native arches (default) — Apple Silicon + Intel DMGs:
./scripts/release-macos-dmg.sh

# One arch only:
ARCH=arm64 ./scripts/release-macos-dmg.sh
ARCH=intel ./scripts/release-macos-dmg.sh

# Skip notary / keep version:
SKIP_NOTARIZE=1 SKIP_BUMP=1 ARCH=arm64 ./scripts/release-macos-dmg.sh

# Version controls:
#   BUMP=patch|minor|major|build   (default: patch — also always +1 build)
#   SKIP_BUMP=1                    keep app/pubspec.yaml as-is
```

Each release rewrites `app/pubspec.yaml`, `core/Cargo.toml`, and the default
`MAC_DMG_VERSION` in `web/src/lib/downloads.ts`.

Outputs (rolling alpha, no version archives):
- `mutande-alpha-arm64.dmg` — Apple Silicon (also copied to `mutande-alpha.dmg`)
- `mutande-alpha-intel.dmg` — Intel

Copy those into `web/public/downloads/` before deploying (DMGs are gitignored).

## Release (Windows unsigned zip)

```text
GitHub → Actions → "Release Windows alpha" → Run workflow
→ download mutande-alpha-windows.zip artifact
→ copy into web/public/downloads/ → deploy site
```

Zip contents: Flutter `Release/` folder + `mutande-core.exe` sidecar (HTTP on
`127.0.0.1:3847`). No codesign / no MSIX.

## Intended path (Sparkle)

1. Sign and notarize `mutande.app` (Developer ID) — script above.
2. Embed [Sparkle](https://sparkle-project.org/) in the Flutter macOS Runner
   (native Swift/`AppDelegate` or a thin plugin).
3. Host an `appcast.xml` (GitHub Releases or CDN) with EdDSA signatures.
4. Menu: **Check for Updates…** on the tray / Session tab.

## Until Sparkle

- Ship fixes by redistributing a new `.dmg`.
- `mutande-core` is bundled as a sidecar in `Contents/Resources/mutande-core`
  (see `app/macos/Runner/Scripts/bundle_mutande_core.sh`); bump both app and
  core together.
- Version: `app/pubspec.yaml` (`version:`) and `core/Cargo.toml`.
