#!/usr/bin/env bash
# Upload alpha installers to Cloudflare R2 under downloads/ (public CDN).
# Does NOT touch blobs/ — mail payloads stay private + presigned.
#
# Prereqs:
#   - aws CLI
#   - R2_ACCOUNT_ID + write creds for mutande-releases
#   - Prefer R2_DOWNLOADS_ACCESS_KEY_ID / R2_DOWNLOADS_SECRET_ACCESS_KEY
#     (hub R2_* is often blobs-only and gets AccessDenied on releases)
#   - Public CDN: https://downloads.mutande.online
#   - NEXT_PUBLIC_DOWNLOADS_BASE on Vercel = that origin (no trailing slash)
#
# Usage (from repo root):
#   ./scripts/upload-downloads-r2.sh
#   ./scripts/upload-downloads-r2.sh dist/macos/mutande-alpha.dmg
#   ./scripts/upload-downloads-r2.sh mutande-alpha-windows.zip
#   SRC_DIR=web/public/downloads ./scripts/upload-downloads-r2.sh
#
# Mac: run after scripts/release-macos-dmg.sh
# Windows: GitHub Actions "Release Windows alpha" runs this automatically
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/hub/.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  # Only pull R2_* — avoid sourcing unrelated secrets into the shell dump.
  while IFS= read -r line; do
    case "$line" in
      R2_*=*) eval "export ${line}" ;;
    esac
  done < <(grep -E '^R2_[A-Z0-9_]+=' "$ROOT/hub/.env" || true)
  set +a
fi

: "${R2_ACCOUNT_ID:?set R2_ACCOUNT_ID}"

# Downloads-scoped keys win over hub blobs keys.
R2_ACCESS_KEY_ID="${R2_DOWNLOADS_ACCESS_KEY_ID:-${R2_ACCESS_KEY_ID:-}}"
R2_SECRET_ACCESS_KEY="${R2_DOWNLOADS_SECRET_ACCESS_KEY:-${R2_SECRET_ACCESS_KEY:-}}"
: "${R2_ACCESS_KEY_ID:?set R2_DOWNLOADS_ACCESS_KEY_ID or R2_ACCESS_KEY_ID}"
: "${R2_SECRET_ACCESS_KEY:?set R2_DOWNLOADS_SECRET_ACCESS_KEY or R2_SECRET_ACCESS_KEY}"

# Public installers go to mutande-releases (custom domain / r2.dev).
# Keep mail blobs in mutande-blobs (private).
R2_BUCKET="${R2_DOWNLOADS_BUCKET:-mutande-releases}"

ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
# Flat keys at bucket root so public URL is $BASE/mutande-alpha.dmg
PREFIX="${R2_DOWNLOADS_PREFIX:-}"
SRC_DIR="${SRC_DIR:-}"

export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION=auto
# Avoid picking up unrelated AWS profiles.
export AWS_PROFILE=
unset AWS_PROFILE

upload_one() {
  local file="$1"
  local base
  base="$(basename "$file")"
  local key="$base"
  if [[ -n "$PREFIX" ]]; then
    key="${PREFIX%/}/${base}"
  fi
  local ctype="application/octet-stream"
  case "$base" in
    *.dmg) ctype="application/x-apple-diskimage" ;;
    *.zip) ctype="application/zip" ;;
  esac
  echo "==> s3://${R2_BUCKET}/${key}"
  aws s3 cp "$file" "s3://${R2_BUCKET}/${key}" \
    --endpoint-url "$ENDPOINT" \
    --content-type "$ctype" \
    --cache-control "public, max-age=300"
}

FILES=("$@")
if [[ ${#FILES[@]} -eq 0 ]]; then
  if [[ -n "$SRC_DIR" ]]; then
    while IFS= read -r -d '' f; do
      FILES+=("$f")
    done < <(find "$SRC_DIR" \( -name '*.dmg' -o -name '*.zip' \) -type f -print0 | sort -z)
  else
    for cand in \
      dist/macos/mutande-alpha.dmg \
      dist/macos/mutande-alpha-arm64.dmg \
      dist/macos/mutande-alpha-intel.dmg \
      web/public/downloads/mutande-alpha.dmg \
      web/public/downloads/mutande-alpha-arm64.dmg \
      web/public/downloads/mutande-alpha-intel.dmg \
      web/public/downloads/mutande-alpha-windows.zip \
      mutande-alpha-windows.zip
    do
      [[ -f "$cand" ]] && FILES+=("$cand")
    done
  fi
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "error: no .dmg/.zip found. Pass paths or set SRC_DIR=…" >&2
  exit 1
fi

# Dedupe by basename (prefer first occurrence). macOS bash 3.2-safe.
UNIQUE=()
for f in "${FILES[@]}"; do
  b="$(basename "$f")"
  skip=0
  for u in "${UNIQUE[@]+"${UNIQUE[@]}"}"; do
    if [[ "$(basename "$u")" == "$b" ]]; then
      skip=1
      break
    fi
  done
  [[ $skip -eq 1 ]] && continue
  UNIQUE+=("$f")
done

for f in "${UNIQUE[@]}"; do
  upload_one "$f"
done

PUBLIC_BASE="${R2_DOWNLOADS_PUBLIC_BASE:-${NEXT_PUBLIC_DOWNLOADS_BASE:-https://downloads.mutande.online}}"
PUBLIC_BASE="${PUBLIC_BASE%/}"
echo ""
echo "Uploaded ${#UNIQUE[@]} object(s) to s3://${R2_BUCKET}/"
echo "Public URLs (Vercel NEXT_PUBLIC_DOWNLOADS_BASE=${PUBLIC_BASE}):"
for f in "${UNIQUE[@]}"; do
  if [[ -n "$PREFIX" ]]; then
    echo "  ${PUBLIC_BASE}/${PREFIX%/}/$(basename "$f")"
  else
    echo "  ${PUBLIC_BASE}/$(basename "$f")"
  fi
done
