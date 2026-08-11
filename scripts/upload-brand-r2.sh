#!/usr/bin/env bash
# Upload landing/marketing brand media to Cloudflare R2 (public CDN).
# Objects land under brand/ on mutande-releases:
#   https://downloads.mutande.online/brand/landing-intro.mp4
#
# Prereqs: same R2_DOWNLOADS_* as scripts/upload-downloads-r2.sh
#
# Usage (from repo root):
#   ./scripts/upload-brand-r2.sh
#   ./scripts/upload-brand-r2.sh web/public/brand/landing-intro.mp4
#   SRC_DIR=web/public/brand ./scripts/upload-brand-r2.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/hub/.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  while IFS= read -r line; do
    case "$line" in
      R2_*=*) eval "export ${line}" ;;
    esac
  done < <(grep -E '^R2_[A-Z0-9_]+=' "$ROOT/hub/.env" || true)
  set +a
fi

: "${R2_ACCOUNT_ID:?set R2_ACCOUNT_ID}"

R2_ACCESS_KEY_ID="${R2_DOWNLOADS_ACCESS_KEY_ID:-${R2_ACCESS_KEY_ID:-}}"
R2_SECRET_ACCESS_KEY="${R2_DOWNLOADS_SECRET_ACCESS_KEY:-${R2_SECRET_ACCESS_KEY:-}}"
: "${R2_ACCESS_KEY_ID:?set R2_DOWNLOADS_ACCESS_KEY_ID or R2_ACCESS_KEY_ID}"
: "${R2_SECRET_ACCESS_KEY:?set R2_DOWNLOADS_SECRET_ACCESS_KEY or R2_SECRET_ACCESS_KEY}"

R2_BUCKET="${R2_DOWNLOADS_BUCKET:-mutande-releases}"
ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
PREFIX="${R2_BRAND_PREFIX:-brand}"
SRC_DIR="${SRC_DIR:-}"

export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION=auto
export AWS_PROFILE=
unset AWS_PROFILE

upload_one() {
  local file="$1"
  local base
  base="$(basename "$file")"
  local key="${PREFIX%/}/${base}"
  local ctype="application/octet-stream"
  local cache="public, max-age=31536000, immutable"
  case "$base" in
    *.mp4) ctype="video/mp4" ;;
    *.webm) ctype="video/webm" ;;
    *.png) ctype="image/png" ;;
    *.jpg|*.jpeg) ctype="image/jpeg" ;;
    *.webp) ctype="image/webp" ;;
    *.svg) ctype="image/svg+xml" ;;
  esac
  echo "==> s3://${R2_BUCKET}/${key} (${ctype})"
  aws s3 cp "$file" "s3://${R2_BUCKET}/${key}" \
    --endpoint-url "$ENDPOINT" \
    --content-type "$ctype" \
    --cache-control "$cache"
}

FILES=("$@")
if [[ ${#FILES[@]} -eq 0 ]]; then
  if [[ -n "$SRC_DIR" ]]; then
    while IFS= read -r -d '' f; do
      FILES+=("$f")
    done < <(find "$SRC_DIR" \( \
      -name 'landing-intro.mp4' -o \
      -name 'landing-intro.webm' -o \
      -name 'landing-intro-poster.png' -o \
      -name 'landing-intro-poster.webp' \
    \) -type f -print0 | sort -z)
  else
    for cand in \
      web/public/brand/landing-intro.mp4 \
      web/public/brand/landing-intro.webm \
      web/public/brand/landing-intro-poster.webp \
      web/public/brand/landing-intro-poster.png
    do
      [[ -f "$cand" ]] && FILES+=("$cand")
    done
  fi
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "error: no landing-intro media found under web/public/brand/. Pass paths or set SRC_DIR=…" >&2
  exit 1
fi

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
echo "Uploaded ${#UNIQUE[@]} object(s) to s3://${R2_BUCKET}/${PREFIX%/}/"
echo "Public URLs:"
for f in "${UNIQUE[@]}"; do
  echo "  ${PUBLIC_BASE}/${PREFIX%/}/$(basename "$f")"
done
