#!/bin/bash
# Copy mutande-core into the macOS app bundle Resources for sidecar launch.
# Invoked from an Xcode Run Script build phase on the Runner target.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# app/macos/Runner/Scripts → repo root is ../../../../
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
CORE_DIR="$REPO_ROOT/core"

RESOURCES_DIR="${BUILT_PRODUCTS_DIR:-}/${CONTENTS_FOLDER_PATH:-Contents}/Resources"
mkdir -p "$RESOURCES_DIR"

# Prefer release; fall back to debug for local `flutter run`.
CANDIDATES=(
  "$CORE_DIR/target/release/mutande-core"
  "$CORE_DIR/target/debug/mutande-core"
)

SRC=""
for c in "${CANDIDATES[@]}"; do
  if [[ -x "$c" ]]; then
    SRC="$c"
    break
  fi
done

if [[ -z "$SRC" ]]; then
  echo "warning: mutande-core binary not found under core/target/{release,debug}."
  echo "         Build with: (cd core && cargo build --release)"
  echo "         Skipping bundle copy — set MUTANDE_CORE_PATH at runtime for Connect AI."
  exit 0
fi

DEST="$RESOURCES_DIR/mutande-core"
cp -f "$SRC" "$DEST"
chmod 755 "$DEST"
echo "Bundled mutande-core → $DEST"
