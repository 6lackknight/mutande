#!/usr/bin/env bash
# Build, Developer ID–sign, optionally notarize, and package mutande as a DMG.
#
# Prereqs:
#   - Developer ID Application cert in Keychain
#   - Flutter + Rust toolchain
#   - For notarization: keychain profile from
#       xcrun notarytool store-credentials "mutande-notary" \
#         --apple-id "you@example.com" --team-id "Q22P2YXR6M" --password "<app-specific-password>"
#
# Usage (from repo root):
#   ./scripts/release-macos-dmg.sh
#   SKIP_NOTARIZE=1 ./scripts/release-macos-dmg.sh
#   BUMP=patch|minor|major|build ./scripts/release-macos-dmg.sh   # default: patch
#   SKIP_BUMP=1 ./scripts/release-macos-dmg.sh                     # keep current version
#   NOTARY_PROFILE=mutande-notary ./scripts/release-macos-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP_DIR="$ROOT/app"
CORE_DIR="$ROOT/core"
DIST_DIR="${DIST_DIR:-$ROOT/dist/macos}"
TEAM_ID="${TEAM_ID:-Q22P2YXR6M}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Tawanda Brandon Holdings (PTY) Ltd. ($TEAM_ID)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-mutande-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
SKIP_BUMP="${SKIP_BUMP:-0}"
BUMP="${BUMP:-patch}"
BUNDLE_ID="ai.mutande.app"

export PATH="${HOME}/.cargo/bin:${HOME}/flutter/bin:/opt/homebrew/bin:${PATH:-}"

echo "==> bump version (BUMP=${BUMP}, SKIP_BUMP=${SKIP_BUMP})"
VERSION_INFO="$(
  BUMP="$BUMP" SKIP_BUMP="$SKIP_BUMP" APP_DIR="$APP_DIR" CORE_DIR="$CORE_DIR" ROOT="$ROOT" python3 - <<'PY'
import os, re
from pathlib import Path

app_dir = Path(os.environ["APP_DIR"])
core_dir = Path(os.environ["CORE_DIR"])
root = Path(os.environ["ROOT"])
bump = os.environ.get("BUMP", "patch")
skip = os.environ.get("SKIP_BUMP", "0") == "1"

pubspec = app_dir / "pubspec.yaml"
text = pubspec.read_text()
m = re.search(r"^version:\s*(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?\s*$", text, re.M)
if not m:
    raise SystemExit("error: could not parse version: in app/pubspec.yaml")
major, minor, patch, build = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4) or "0")
old = f"{major}.{minor}.{patch}+{build}"

if not skip:
    if bump == "major":
        major, minor, patch = major + 1, 0, 0
    elif bump == "minor":
        minor, patch = minor + 1, 0
    elif bump == "patch":
        patch += 1
    elif bump == "build":
        pass
    else:
        raise SystemExit(f"error: unknown BUMP={bump!r} (use major|minor|patch|build)")
    build += 1
    new = f"{major}.{minor}.{patch}+{build}"
    text2, n = re.subn(
        r"^version:\s*\d+\.\d+\.\d+(?:\+\d+)?\s*$",
        f"version: {new}",
        text,
        count=1,
        flags=re.M,
    )
    if n != 1:
        raise SystemExit("error: failed to rewrite app/pubspec.yaml version")
    pubspec.write_text(text2)

    cargo = core_dir / "Cargo.toml"
    cargo_text = cargo.read_text()
    cargo2, cn = re.subn(
        r'(?m)^version\s*=\s*"[^"]*"\s*$',
        f'version = "{major}.{minor}.{patch}"',
        cargo_text,
        count=1,
    )
    if cn != 1:
        raise SystemExit("error: failed to rewrite core/Cargo.toml version")
    cargo.write_text(cargo2)

    downloads = root / "web/src/lib/downloads.ts"
    if downloads.exists():
        dtext = downloads.read_text()
        d2, dn = re.subn(
            r'(NEXT_PUBLIC_MAC_DMG_VERSION\s*\?\?\s*")([^"]*)(")',
            rf"\g<1>{major}.{minor}.{patch}\g<3>",
            dtext,
            count=1,
        )
        if dn == 1:
            downloads.write_text(d2)

    print(f"bumped {old} -> {new}", file=__import__("sys").stderr)
else:
    new = old
    print(f"skip bump; using {new}", file=__import__("sys").stderr)

print(f"{major}.{minor}.{patch} {build}")
PY
)"
VERSION="$(echo "$VERSION_INFO" | awk '{print $1}')"
BUILD_NUMBER="$(echo "$VERSION_INFO" | awk '{print $2}')"
DMG_NAME="mutande-${VERSION}.dmg"
APP_NAME="mutande.app"

echo "==> version ${VERSION} (build ${BUILD_NUMBER})"
echo "==> identity ${SIGN_IDENTITY}"

mkdir -p "$DIST_DIR"
rm -rf "$DIST_DIR/${APP_NAME}" "$DIST_DIR/${DMG_NAME}" "$DIST_DIR/.dmg-stage" "$DIST_DIR/${APP_NAME}.zip"

echo "==> cargo build --release (mutande-core)"
(cd "$CORE_DIR" && cargo build --release)

echo "==> flutter build macos --release"
(cd "$APP_DIR" && flutter build macos --release \
  --build-name="${VERSION}" \
  --build-number="${BUILD_NUMBER}")

BUILT_APP="$APP_DIR/build/macos/Build/Products/Release/${APP_NAME}"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: expected app at $BUILT_APP" >&2
  ls -la "$APP_DIR/build/macos/Build/Products/Release/" >&2 || true
  exit 1
fi

cp -R "$BUILT_APP" "$DIST_DIR/${APP_NAME}"
APP="$DIST_DIR/${APP_NAME}"

ENTITLEMENTS="$APP_DIR/macos/Runner/Release.entitlements"
SIDECAR_ENTITLEMENTS="$APP_DIR/macos/Runner/Sidecar.entitlements"
CORE_BIN="$APP/Contents/Resources/mutande-core"

echo "==> codesign nested frameworks + sidecar + app"
if [[ ! -x "$CORE_BIN" ]]; then
  echo "error: missing sidecar $CORE_BIN" >&2
  exit 1
fi

# Inside-out: frameworks (runtime only — no app entitlements), sidecar, then app.
find "$APP/Contents/Frameworks" -name "*.framework" -maxdepth 1 -print0 2>/dev/null \
  | while IFS= read -r -d '' fw; do
      echo "    $(basename "$fw")"
      codesign --force --options runtime --timestamp --deep \
        --sign "$SIGN_IDENTITY" \
        "$fw"
    done

echo "    mutande-core"
codesign --force --options runtime --timestamp \
  --entitlements "$SIDECAR_ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$CORE_BIN"

echo "    ${APP_NAME}"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$APP"

echo "==> verify signature"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP" 2>&1 || true

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  echo "==> zip for notarytool"
  ditto -c -k --keepParent "$APP" "$DIST_DIR/${APP_NAME}.zip"

  echo "==> submit notarization (profile: ${NOTARY_PROFILE})"
  xcrun notarytool submit "$DIST_DIR/${APP_NAME}.zip" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  echo "==> staple"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
else
  echo "==> SKIP_NOTARIZE=1 — Gatekeeper will warn until notarized"
fi

echo "==> build DMG"
STAGE="$DIST_DIR/.dmg-stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"

# UDZO compressed DMG
hdiutil create \
  -volname "mutande" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DIST_DIR/${DMG_NAME}"

rm -rf "$STAGE"

# Disk image must be Developer ID–signed or Gatekeeper reports "no usable signature"
# even when the nested .app is notarized.
echo "==> codesign DMG"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DIST_DIR/${DMG_NAME}"
codesign --verify --verbose=2 "$DIST_DIR/${DMG_NAME}"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  echo "==> notarize + staple DMG"
  xcrun notarytool submit "$DIST_DIR/${DMG_NAME}" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DIST_DIR/${DMG_NAME}"
  xcrun stapler validate "$DIST_DIR/${DMG_NAME}"
fi

# Rolling alpha channel — only this public name is kept (no version archives).
CHANNEL_DMG="mutande-alpha.dmg"
cp -f "$DIST_DIR/${DMG_NAME}" "$DIST_DIR/${CHANNEL_DMG}"
rm -f "$DIST_DIR/${DMG_NAME}" "$DIST_DIR/mutande-latest.dmg"
find "$DIST_DIR" -maxdepth 1 -type f -name 'mutande-*.dmg' ! -name "$CHANNEL_DMG" -delete

echo "==> Gatekeeper assess"
spctl --assess --type execute --verbose=4 "$APP" 2>&1 || true
# open/context is the check users hit when mounting a downloaded DMG
spctl --assess --type open --context context:primary-signature --verbose=4 \
  "$DIST_DIR/${CHANNEL_DMG}" 2>&1 || true

echo ""
echo "Done."
echo "  App:     $APP"
echo "  Version: $DIST_DIR/${DMG_NAME}"
echo "  Publish: $DIST_DIR/${CHANNEL_DMG}"
echo "  Bundle id: $BUNDLE_ID"
echo "  Team: $TEAM_ID"
