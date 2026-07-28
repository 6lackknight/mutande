# macOS updates (Sparkle) — v1 stub

## Status

**DMG release script exists** (`scripts/release-macos-dmg.sh`). Developer ID
signing is wired; **notarization** still needs a one-time Apple credential
profile. Sparkle auto-updates remain deferred (PRD story 37).

## Release (notarized DMG)

```bash
# One-time (Apple ID + app-specific password from appleid.apple.com):
xcrun notarytool store-credentials "mutande-notary" \
  --apple-id "you@example.com" \
  --team-id "Q22P2YXR6M" \
  --password "<app-specific-password>"

# Build, sign, notarize, staple, package (auto-bumps patch + build by default):
./scripts/release-macos-dmg.sh

# Or skip notary while iterating:
SKIP_NOTARIZE=1 ./scripts/release-macos-dmg.sh

# Version controls:
#   BUMP=patch|minor|major|build   (default: patch — also always +1 build)
#   SKIP_BUMP=1                    keep app/pubspec.yaml as-is
```

Each release rewrites `app/pubspec.yaml`, `core/Cargo.toml`, and the default
`MAC_DMG_VERSION` in `web/src/lib/downloads.ts`.

Outputs land in `dist/macos/` (`mutande-VERSION.dmg`, `mutande-latest.dmg`).
Copy into `web/public/downloads/` before deploying the site (DMGs are
gitignored). Optional CDN: set `NEXT_PUBLIC_MAC_DMG_URL` on Vercel.

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
