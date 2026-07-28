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
BUNDLE_ID="ai.mutande.app"

export PATH="${HOME}/.cargo/bin:${HOME}/flutter/bin:/opt/homebrew/bin:${PATH:-}"

VERSION="$(
  python3 - <<PY
import re
from pathlib import Path
text = Path("$APP_DIR/pubspec.yaml").read_text()
m = re.search(r"^version:\\s*([0-9]+\\.[0-9]+\\.[0-9]+)", text, re.M)
print(m.group(1) if m else "0.0.0")
PY
)"
DMG_NAME="mutande-${VERSION}.dmg"
APP_NAME="mutande.app"

echo "==> version ${VERSION}"
echo "==> identity ${SIGN_IDENTITY}"

mkdir -p "$DIST_DIR"
rm -rf "$DIST_DIR/${APP_NAME}" "$DIST_DIR/${DMG_NAME}" "$DIST_DIR/.dmg-stage" "$DIST_DIR/${APP_NAME}.zip"

echo "==> cargo build --release (mutande-core)"
(cd "$CORE_DIR" && cargo build --release)

echo "==> flutter build macos --release"
(cd "$APP_DIR" && flutter build macos --release)

BUILT_APP="$APP_DIR/build/macos/Build/Products/Release/${APP_NAME}"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: expected app at $BUILT_APP" >&2
  ls -la "$APP_DIR/build/macos/Build/Products/Release/" >&2 || true
  exit 1
fi

cp -R "$BUILT_APP" "$DIST_DIR/${APP_NAME}"
APP="$DIST_DIR/${APP_NAME}"

ENTITLEMENTS="$APP_DIR/macos/Runner/Release.entitlements"
CORE_BIN="$APP/Contents/Resources/mutande-core"

echo "==> codesign nested frameworks + sidecar + app"
if [[ ! -x "$CORE_BIN" ]]; then
  echo "error: missing sidecar $CORE_BIN" >&2
  exit 1
fi

# Inside-out: frameworks, then sidecar, then outer app (Flutter-friendly).
find "$APP/Contents/Frameworks" -name "*.framework" -maxdepth 1 -print0 2>/dev/null \
  | while IFS= read -r -d '' fw; do
      echo "    $(basename "$fw")"
      codesign --force --options runtime --timestamp --deep \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        "$fw"
    done

echo "    mutande-core"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
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

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  echo "==> notarize + staple DMG"
  xcrun notarytool submit "$DIST_DIR/${DMG_NAME}" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DIST_DIR/${DMG_NAME}"
fi

# Convenience copy without version for stable website URL
cp -f "$DIST_DIR/${DMG_NAME}" "$DIST_DIR/mutande-latest.dmg"

echo ""
echo "Done."
echo "  App:  $APP"
echo "  DMG:  $DIST_DIR/${DMG_NAME}"
echo "  Also: $DIST_DIR/mutande-latest.dmg"
echo "  Bundle id: $BUNDLE_ID"
echo "  Team: $TEAM_ID"
