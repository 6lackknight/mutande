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

# Prefer arch-specific cargo targets (release script / dual-arch), then host defaults.
ARCHS_VAL="${ARCHS:-${NATIVE_ARCH_ACTUAL:-}}"
CANDIDATES=()
case " ${ARCHS_VAL} " in
  *" arm64 "*|*"arm64"*)
    CANDIDATES+=(
      "$CORE_DIR/target/aarch64-apple-darwin/release/mutande-core"
      "$CORE_DIR/target/aarch64-apple-darwin/debug/mutande-core"
    )
    ;;
esac
case " ${ARCHS_VAL} " in
  *" x86_64 "*|*"x86_64"*)
    CANDIDATES+=(
      "$CORE_DIR/target/x86_64-apple-darwin/release/mutande-core"
      "$CORE_DIR/target/x86_64-apple-darwin/debug/mutande-core"
    )
    ;;
esac
CANDIDATES+=(
  "$CORE_DIR/target/release/mutande-core"
  "$CORE_DIR/target/debug/mutande-core"
  "$CORE_DIR/target/aarch64-apple-darwin/release/mutande-core"
  "$CORE_DIR/target/x86_64-apple-darwin/release/mutande-core"
)

SRC=""
for c in "${CANDIDATES[@]}"; do
  if [[ -x "$c" ]]; then
    SRC="$c"
    break
  fi
done

if [[ -z "$SRC" ]]; then
  echo "warning: mutande-core binary not found under core/target/**."
  echo "         Build with: (cd core && cargo build --release)"
  echo "         or: cargo build --release --target aarch64-apple-darwin"
  echo "         Skipping bundle copy — set MUTANDE_CORE_PATH at runtime for Connect AI."
  exit 0
fi

DEST="$RESOURCES_DIR/mutande-core"
cp -f "$SRC" "$DEST"
chmod 755 "$DEST"
echo "Bundled mutande-core → $DEST (from $SRC)"
