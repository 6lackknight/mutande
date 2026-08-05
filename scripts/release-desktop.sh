#!/usr/bin/env bash
# End-to-end desktop alpha release:
#   1) bump + notarize Mac DMGs (arm64 + intel)
#   2) upload DMGs to mutande-releases (downloads.mutande.online)
#   3) push main (if ahead) and run Windows Actions → publish-r2
#   4) set Vercel version envs + redeploy production web
#
# Prereqs: same as release-macos-dmg.sh + upload-downloads-r2.sh,
#          gh auth, vercel linked to web/, R2_DOWNLOADS_* secrets on the repo.
#
# Usage (from repo root):
#   ./scripts/release-desktop.sh
#   SKIP_BUMP=1 ./scripts/release-desktop.sh
#   SKIP_MAC=1 ./scripts/release-desktop.sh          # Windows + site only
#   SKIP_WINDOWS=1 ./scripts/release-desktop.sh      # Mac + site only
#   SKIP_WEB=1 ./scripts/release-desktop.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="${HOME}/.cargo/bin:${HOME}/flutter/bin:/opt/homebrew/bin:${PATH:-}"

SKIP_BUMP="${SKIP_BUMP:-0}"
SKIP_MAC="${SKIP_MAC:-0}"
SKIP_WINDOWS="${SKIP_WINDOWS:-0}"
SKIP_WEB="${SKIP_WEB:-0}"
ARCH="${ARCH:-both}"
WAIT_WINDOWS="${WAIT_WINDOWS:-1}"

version_semver() {
  python3 - <<'PY'
from pathlib import Path
import re
text = Path("app/pubspec.yaml").read_text()
m = re.search(r"^version:\s*(\d+\.\d+\.\d+)", text, re.M)
print(m.group(1) if m else "")
PY
}

if [[ "$SKIP_MAC" != "1" ]]; then
  echo "==> Mac notarized DMGs (ARCH=${ARCH})"
  rm -rf dist/macos
  mkdir -p dist/macos
  # Drop stale Flutter Products so reuse cannot skip a real rebuild.
  rm -rf app/build/macos/Build/Products/Release
  SKIP_BUMP="$SKIP_BUMP" ARCH="$ARCH" ./scripts/release-macos-dmg.sh
  ./scripts/upload-downloads-r2.sh \
    dist/macos/mutande-alpha.dmg \
    dist/macos/mutande-alpha-arm64.dmg \
    dist/macos/mutande-alpha-intel.dmg
  mkdir -p web/public/downloads
  cp -f dist/macos/mutande-alpha*.dmg web/public/downloads/ 2>/dev/null || true
else
  echo "==> SKIP_MAC=1"
fi

VER="$(version_semver)"
if [[ -z "$VER" ]]; then
  echo "error: could not read app/pubspec.yaml version" >&2
  exit 1
fi
echo "==> version ${VER}"

if [[ "$SKIP_WINDOWS" != "1" ]]; then
  echo "==> ensure main is pushed, then Release Windows alpha"
  git push -u origin HEAD
  gh workflow run "Release Windows alpha" --ref "$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$WAIT_WINDOWS" == "1" ]]; then
    RUN_ID="$(gh run list --workflow='Release Windows alpha' --limit 1 --json databaseId -q '.[0].databaseId')"
    echo "==> watching Windows run ${RUN_ID}"
    gh run watch "$RUN_ID" --exit-status
  fi
else
  echo "==> SKIP_WINDOWS=1"
fi

if [[ "$SKIP_WEB" != "1" ]]; then
  echo "==> Vercel version envs + production redeploy"
  (
    cd web
    for env in production development; do
      printf '%s' "$VER" | vercel env add NEXT_PUBLIC_MAC_DMG_VERSION "$env" --force --yes >/dev/null
      printf '%s' "$VER" | vercel env add NEXT_PUBLIC_WIN_ZIP_VERSION "$env" --force --yes >/dev/null
    done
    # Keep published flags on (idempotent if already set).
    printf '1' | vercel env add NEXT_PUBLIC_MAC_INTEL_PUBLISHED production --force --yes >/dev/null || true
    printf '1' | vercel env add NEXT_PUBLIC_WIN_ZIP_PUBLISHED production --force --yes >/dev/null || true
    LATEST="$(vercel ls --prod 2>/dev/null | awk '/https:\/\/mutande-.*\.vercel\.app/ {print $3; exit}')"
    if [[ -z "$LATEST" ]]; then
      echo "error: could not find a production deployment to redeploy" >&2
      exit 1
    fi
    vercel redeploy "$LATEST" --target production
  )
else
  echo "==> SKIP_WEB=1"
fi

echo ""
echo "Desktop release complete (${VER})."
echo "  https://downloads.mutande.online/mutande-alpha.dmg"
echo "  https://downloads.mutande.online/mutande-alpha-intel.dmg"
echo "  https://downloads.mutande.online/mutande-alpha-windows.zip"
echo "  https://mutande.online/download"
