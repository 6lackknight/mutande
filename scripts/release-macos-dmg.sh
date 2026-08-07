#!/usr/bin/env bash
# Build, Developer ID–sign, optionally notarize, and package mutande DMGs.
#
# Two architecture paths (native binaries — no Rosetta required):
#   ARCH=arm64  → mutande-alpha-arm64.dmg   (Apple Silicon)
#   ARCH=intel  → mutande-alpha-intel.dmg   (Intel)
#   ARCH=both   → both (default)
#
# Prereqs:
#   - Developer ID Application cert in Keychain
#   - Flutter + Rust toolchain (+ rustup target aarch64-apple-darwin when building arm64)
#   - For notarization: keychain profile "mutande-notary"
#
# Usage (from repo root):
#   ./scripts/release-macos-dmg.sh
#   ARCH=arm64 ./scripts/release-macos-dmg.sh
#   ARCH=intel SKIP_NOTARIZE=1 SKIP_BUMP=1 ./scripts/release-macos-dmg.sh
#   BUMP=patch|minor|major|build   (default: patch)
#   SKIP_BUMP=1
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
ARCH="${ARCH:-both}"
BUNDLE_ID="ai.mutande.app"
APP_NAME="mutande.app"

export PATH="${HOME}/.cargo/bin:${HOME}/flutter/bin:/opt/homebrew/bin:${PATH:-}"
# Cursor/agent shells may redirect Cargo into a sandbox cache; releases must
# write into the repo's core/target so Flutter packaging picks up the sidecar.
unset CARGO_TARGET_DIR

ENTITLEMENTS="$APP_DIR/macos/Runner/Release.entitlements"
SIDECAR_ENTITLEMENTS="$APP_DIR/macos/Runner/Sidecar.entitlements"

resolve_arch() {
  case "$1" in
    arm64|aarch64|apple-silicon|silicon) echo "arm64" ;;
    intel|x86_64|x64|amd64) echo "intel" ;;
    both|all) echo "both" ;;
    *)
      echo "error: unknown ARCH=$1 (use arm64|intel|both)" >&2
      exit 1
      ;;
  esac
}

rust_target_for() {
  case "$1" in
    arm64) echo "aarch64-apple-darwin" ;;
    intel) echo "x86_64-apple-darwin" ;;
  esac
}

macho_arch_for() {
  case "$1" in
    arm64) echo "arm64" ;;
    intel) echo "x86_64" ;;
  esac
}

channel_dmg_for() {
  case "$1" in
    arm64) echo "mutande-alpha-arm64.dmg" ;;
    intel) echo "mutande-alpha-intel.dmg" ;;
  esac
}

ensure_rust_target() {
  local target="$1"
  if ! rustup target list --installed | grep -qx "$target"; then
    echo "==> rustup target add ${target}"
    rustup target add "$target"
  fi
}

thin_app_to_arch() {
  local app="$1"
  local slice="$2"
  echo "==> thin app to ${slice}"
  while IFS= read -r -d '' f; do
    [[ -L "$f" ]] && continue
    local kind
    kind="$(file -b "$f" 2>/dev/null || true)"
    [[ "$kind" == *Mach-O* ]] || continue
    local archs
    archs="$(lipo -archs "$f" 2>/dev/null || true)"
    [[ -n "$archs" ]] || continue
    if ! echo " $archs " | grep -q " ${slice} "; then
      echo "    warning: no ${slice} slice in ${f#"$app/"}" >&2
      continue
    fi
    # shellcheck disable=SC2206
    local -a list=($archs)
    if [[ ${#list[@]} -gt 1 ]]; then
      lipo -thin "$slice" "$f" -output "${f}.thin"
      mv "${f}.thin" "$f"
    fi
  done < <(find "$app" -type f -print0)
}

sign_app() {
  local app="$1"
  local core_bin="$app/Contents/Resources/mutande-core"

  echo "==> codesign nested frameworks + sidecar + app"
  if [[ ! -x "$core_bin" ]]; then
    echo "error: missing sidecar $core_bin" >&2
    exit 1
  fi

  find "$app/Contents/Frameworks" -name "*.framework" -maxdepth 1 -print0 2>/dev/null \
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
    "$core_bin"

  echo "    ${APP_NAME}"
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$app"

  codesign --verify --deep --strict --verbose=2 "$app"
  spctl --assess --type execute --verbose=4 "$app" 2>&1 || true
}

notarize_app() {
  local app="$1"
  local zip="$DIST_DIR/${APP_NAME}.${2}.zip"
  echo "==> zip + notarize app (${2})"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  rm -f "$zip"
}

package_dmg() {
  local app="$1"
  local dmg_path="$2"
  local stage="$DIST_DIR/.dmg-stage-$3"

  echo "==> build DMG $(basename "$dmg_path")"
  rm -rf "$stage" "$dmg_path"
  mkdir -p "$stage"
  cp -R "$app" "$stage/"
  ln -sf /Applications "$stage/Applications"
  hdiutil create \
    -volname "mutande" \
    -srcfolder "$stage" \
    -ov \
    -format UDZO \
    "$dmg_path"
  rm -rf "$stage"

  echo "==> codesign DMG"
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$dmg_path"
  codesign --verify --verbose=2 "$dmg_path"

  if [[ "$SKIP_NOTARIZE" != "1" ]]; then
    echo "==> notarize + staple DMG"
    xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg_path"
    xcrun stapler validate "$dmg_path"
  fi

  spctl --assess --type open --context context:primary-signature --verbose=4 \
    "$dmg_path" 2>&1 || true
}

build_one_arch() {
  local arch_key="$1"
  local rust_target
  local macho
  local channel_dmg
  local app_out
  local core_src
  local built_app

  rust_target="$(rust_target_for "$arch_key")"
  macho="$(macho_arch_for "$arch_key")"
  channel_dmg="$(channel_dmg_for "$arch_key")"
  app_out="$DIST_DIR/${APP_NAME}.${arch_key}"
  ensure_rust_target "$rust_target"

  echo ""
  echo "========== ARCH=${arch_key} (${rust_target}) =========="

  echo "==> cargo build --release --target ${rust_target}"
  (cd "$CORE_DIR" && cargo build --release --target "$rust_target")
  core_src="$CORE_DIR/target/${rust_target}/release/mutande-core"
  if [[ ! -x "$core_src" ]]; then
    echo "error: missing $core_src" >&2
    exit 1
  fi

  # Fail the cut if Flutter/app version and embedded core disagree (avoids
  # shipping app vX with Resources/mutande-core still on X-1).
  # Prefer clap --version when the binary can run on this host; cross-arch
  # builds (Intel host → arm64 sidecar) cannot exec, so fall back to the
  # embedded CARGO_PKG_VERSION / clap version string in the Mach-O.
  core_ver=""
  set +e
  core_ver="$("$core_src" --version 2>/dev/null | awk '{print $NF}' | tr -d '[:space:]')"
  core_ver_rc=$?
  set -e
  if [[ -z "$core_ver" || "$core_ver_rc" -ne 0 ]]; then
    if grep -aobF "$VERSION" "$core_src" >/dev/null 2>&1; then
      core_ver="$VERSION"
      echo "==> mutande-core embeds ${core_ver} (cross-arch; --version not runnable here)"
    else
      echo "error: could not verify version of $core_src (expected ${VERSION})" >&2
      echo "       sync core/Cargo.toml with app/pubspec.yaml and rebuild (cargo clean -p mutande-core)" >&2
      exit 1
    fi
  fi
  if [[ "$core_ver" != "$VERSION" ]]; then
    echo "error: mutande-core is v${core_ver} but release VERSION is ${VERSION}" >&2
    echo "       sync core/Cargo.toml with app/pubspec.yaml and rebuild" >&2
    exit 1
  fi
  echo "==> mutande-core --version ${core_ver} (matches app ${VERSION})"

  # Flutter produces a universal (or host) app; we thin + swap sidecar per arch.
  built_app="$APP_DIR/build/macos/Build/Products/Release/${APP_NAME}"
  if [[ ! -x "$built_app/Contents/MacOS/mutande" ]]; then
    echo "==> flutter build macos --release"
    (cd "$APP_DIR" && flutter build macos --release \
      --build-name="${VERSION}" \
      --build-number="${BUILD_NUMBER}" \
      --dart-define="APP_VERSION=${VERSION}")
  else
    echo "==> reuse flutter Release app (already built this run)"
  fi

  if [[ ! -x "$built_app/Contents/MacOS/mutande" ]]; then
    echo "error: expected app binary at $built_app/Contents/MacOS/mutande" >&2
    exit 1
  fi

  rm -rf "$app_out"
  cp -R "$built_app" "$app_out"
  mkdir -p "$app_out/Contents/Resources"
  cp -f "$core_src" "$app_out/Contents/Resources/mutande-core"
  chmod 755 "$app_out/Contents/Resources/mutande-core"
  thin_app_to_arch "$app_out" "$macho"

  echo "==> arch check"
  file "$app_out/Contents/MacOS/mutande"
  file "$app_out/Contents/Resources/mutande-core"
  lipo -archs "$app_out/Contents/MacOS/mutande"
  lipo -archs "$app_out/Contents/Resources/mutande-core"

  sign_app "$app_out"

  if [[ "$SKIP_NOTARIZE" != "1" ]]; then
    notarize_app "$app_out" "$arch_key"
  else
    echo "==> SKIP_NOTARIZE=1 — Gatekeeper will warn until notarized"
  fi

  package_dmg "$app_out" "$DIST_DIR/${channel_dmg}" "$arch_key"

  # Apple Silicon is the default /downloads/mutande-alpha.dmg alias.
  if [[ "$arch_key" == "arm64" ]]; then
    cp -f "$DIST_DIR/${channel_dmg}" "$DIST_DIR/mutande-alpha.dmg"
  fi

  echo "==> done ${arch_key} → ${channel_dmg}"
}

# --- version bump (once per invocation) ---
ARCH="$(resolve_arch "$ARCH")"

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
    # Keep Cargo.toml locked to pubspec even when skipping the bump —
    # otherwise SKIP_BUMP can ship app vX with a stale core crate version.
    cargo = core_dir / "Cargo.toml"
    cargo_text = cargo.read_text()
    cargo2, cn = re.subn(
        r'(?m)^version\s*=\s*"[^"]*"\s*$',
        f'version = "{major}.{minor}.{patch}"',
        cargo_text,
        count=1,
    )
    if cn != 1:
        raise SystemExit("error: failed to sync core/Cargo.toml version")
    if cargo2 != cargo_text:
        cargo.write_text(cargo2)
        print(
            f"skip bump; synced Cargo.toml -> {major}.{minor}.{patch}",
            file=__import__("sys").stderr,
        )
    else:
        print(f"skip bump; using {new}", file=__import__("sys").stderr)

print(f"{major}.{minor}.{patch} {build}")
PY
)"
VERSION="$(echo "$VERSION_INFO" | awk '{print $1}')"
BUILD_NUMBER="$(echo "$VERSION_INFO" | awk '{print $2}')"

echo "==> version ${VERSION} (build ${BUILD_NUMBER})"
echo "==> ARCH=${ARCH}"
echo "==> identity ${SIGN_IDENTITY}"

mkdir -p "$DIST_DIR"
# Fresh flutter build once for this run
rm -rf "$APP_DIR/build/macos/Build/Products/Release/${APP_NAME}"

case "$ARCH" in
  both)
    build_one_arch arm64
    build_one_arch intel
    ;;
  arm64|intel)
    build_one_arch "$ARCH"
    ;;
esac

# Keep only rolling alpha DMGs (+ optional legacy alias).
find "$DIST_DIR" -maxdepth 1 -type f -name 'mutande-*.dmg' \
  ! -name 'mutande-alpha-arm64.dmg' \
  ! -name 'mutande-alpha-intel.dmg' \
  ! -name 'mutande-alpha.dmg' \
  -delete

echo ""
echo "Done."
echo "  Version: ${VERSION}+${BUILD_NUMBER}"
ls -lh "$DIST_DIR"/mutande-alpha*.dmg 2>/dev/null || true
echo "  Bundle id: $BUNDLE_ID"
echo "  Team: $TEAM_ID"
