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

# Sandbox/agent shells sometimes point cargo at a disposable cache — never use that
# for the binary we ship into the app bundle.
unset CARGO_TARGET_DIR

ARCHS_VAL="${ARCHS:-${NATIVE_ARCH_ACTUAL:-$(uname -m)}}"
WANT_ARM64=0
WANT_X86_64=0
case " ${ARCHS_VAL} " in
  *" arm64 "*|*"arm64"*) WANT_ARM64=1 ;;
esac
case " ${ARCHS_VAL} " in
  *" x86_64 "*|*"x86_64"*) WANT_X86_64=1 ;;
esac
# uname -m fallbacks
case "${ARCHS_VAL}" in
  arm64|aarch64) WANT_ARM64=1 ;;
  x86_64|i386) WANT_X86_64=1 ;;
esac

bin_archs() {
  local path="$1"
  if command -v lipo >/dev/null 2>&1; then
    lipo -archs "$path" 2>/dev/null || true
  else
    file -b "$path" 2>/dev/null || true
  fi
}

arch_compatible() {
  local path="$1"
  local archs
  archs="$(bin_archs "$path")"
  [[ -z "$archs" ]] && return 0
  if [[ "$WANT_ARM64" -eq 1 && "$WANT_X86_64" -eq 1 ]]; then
    # Universal Flutter build: accept either; release script lipos for DMG.
    return 0
  fi
  if [[ "$WANT_ARM64" -eq 1 ]]; then
    [[ "$archs" == *arm64* || "$archs" == *aarch64* ]] && return 0
    return 1
  fi
  if [[ "$WANT_X86_64" -eq 1 ]]; then
    [[ "$archs" == *x86_64* ]] && return 0
    return 1
  fi
  return 0
}

# Newest mtime among existing executables (optionally arch-filtered).
pick_newest() {
  local require_arch="${1:-0}"
  local best="" best_mtime=0
  local c m
  for c in "${CANDIDATES[@]}"; do
    [[ -x "$c" ]] || continue
    if [[ "$require_arch" -eq 1 ]] && ! arch_compatible "$c"; then
      continue
    fi
    m="$(stat -f '%m' "$c" 2>/dev/null || echo 0)"
    if [[ "$m" -gt "$best_mtime" ]]; then
      best="$c"
      best_mtime="$m"
    fi
  done
  if [[ -n "$best" ]]; then
    printf '%s' "$best"
  fi
}

sources_newer_than() {
  local bin="$1"
  [[ -x "$bin" ]] || return 0
  local bin_mtime src_mtime
  bin_mtime="$(stat -f '%m' "$bin")"
  src_mtime="$(
    {
      find "$CORE_DIR/src" -type f \( -name '*.rs' -o -name '*.toml' \) -print0 2>/dev/null
      printf '%s\0' "$CORE_DIR/Cargo.toml"
      [[ -f "$CORE_DIR/Cargo.lock" ]] && printf '%s\0' "$CORE_DIR/Cargo.lock"
    } | xargs -0 stat -f '%m' 2>/dev/null | sort -n | tail -1
  )"
  [[ -n "${src_mtime:-}" && "$src_mtime" -gt "$bin_mtime" ]]
}

cargo_release_build() {
  local -a args=(build --release)
  # Prefer explicit triple when Xcode asks for one arch and host default may differ.
  if [[ "$WANT_ARM64" -eq 1 && "$WANT_X86_64" -eq 0 ]]; then
    args+=(--target aarch64-apple-darwin)
  elif [[ "$WANT_X86_64" -eq 1 && "$WANT_ARM64" -eq 0 ]]; then
    args+=(--target x86_64-apple-darwin)
  fi
  echo "note: building mutande-core (${args[*]}) …"
  (cd "$CORE_DIR" && cargo "${args[@]}")
}

CANDIDATES=(
  "$CORE_DIR/target/release/mutande-core"
  "$CORE_DIR/target/debug/mutande-core"
  "$CORE_DIR/target/aarch64-apple-darwin/release/mutande-core"
  "$CORE_DIR/target/aarch64-apple-darwin/debug/mutande-core"
  "$CORE_DIR/target/x86_64-apple-darwin/release/mutande-core"
  "$CORE_DIR/target/x86_64-apple-darwin/debug/mutande-core"
)

SRC="$(pick_newest 1 || true)"
if [[ -z "$SRC" ]]; then
  SRC="$(pick_newest 0 || true)"
fi

if [[ -z "$SRC" ]] || sources_newer_than "$SRC"; then
  if ! command -v cargo >/dev/null 2>&1; then
    # cargo often lives only in interactive shells
    # shellcheck disable=SC1090
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
  fi
  if command -v cargo >/dev/null 2>&1; then
    cargo_release_build
    SRC="$(pick_newest 1 || true)"
    if [[ -z "$SRC" ]]; then
      SRC="$(pick_newest 0 || true)"
    fi
  elif [[ -z "$SRC" ]]; then
    echo "error: mutande-core binary not found under core/target/** and cargo is unavailable."
    echo "       Build with: (cd core && cargo build --release)"
    exit 1
  else
    echo "warning: mutande-core sources look newer than $SRC but cargo is unavailable; bundling as-is."
  fi
fi

if [[ -z "$SRC" ]]; then
  echo "error: mutande-core binary not found under core/target/** after build."
  exit 1
fi

if ! arch_compatible "$SRC"; then
  echo "error: chosen mutande-core is not compatible with ARCHS=${ARCHS_VAL}:"
  echo "       $SRC ($(bin_archs "$SRC"))"
  exit 1
fi

DEST="$RESOURCES_DIR/mutande-core"
cp -f "$SRC" "$DEST"
chmod 755 "$DEST"
echo "Bundled mutande-core → $DEST"
echo "  from $SRC ($(bin_archs "$SRC"), mtime $(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$SRC"))"
