#!/usr/bin/env bash
# Derive web / Flutter / video / AppIcon brand rasters from brand/sources/.
#
# Usage (from repo root):
#   ./scripts/sync-brand-assets.sh
#
# Requires: sips (macOS), dart/flutter in PATH for AppIcon regen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SRC="$ROOT/brand/sources"
WEB="$ROOT/web/public/brand"
APP_ASSETS="$ROOT/app/assets"
VIDEO="$ROOT/video/public/brand"

AI_MARK="$SRC/ai-mark.png"
AI_TRAY="$SRC/ai-tray.png"
LIGATURE="$SRC/mt-ligature.png"

for f in "$AI_MARK" "$AI_TRAY" "$LIGATURE"; do
  if [[ ! -f "$f" ]]; then
    echo "error: missing master $f" >&2
    exit 1
  fi
done

mkdir -p "$WEB" "$APP_ASSETS" "$VIDEO"

# Resize master → dest (square). Copies when already the target size.
resize_square() {
  local src="$1"
  local dest="$2"
  local px="$3"
  local tmp
  tmp="$(mktemp -t mutande-brand.XXXXXX).png"
  # sips writes in place relative to its output; use a temp then mv for atomicity.
  cp "$src" "$tmp"
  sips -z "$px" "$px" "$tmp" >/dev/null
  mv "$tmp" "$dest"
  echo "  $(basename "$dest") (${px}×${px})"
}

copy_file() {
  local src="$1"
  local dest="$2"
  cp "$src" "$dest"
  echo "  $(basename "$dest") (copy)"
}

echo "==> @i seal (ai-mark.png)"
resize_square "$AI_MARK" "$APP_ASSETS/app_icon.png" 1024
resize_square "$AI_MARK" "$WEB/mt-mark.png" 512
resize_square "$AI_MARK" "$WEB/icon-192.png" 192
resize_square "$AI_MARK" "$WEB/apple-touch-icon.png" 180
resize_square "$AI_MARK" "$WEB/favicon-32.png" 32
resize_square "$AI_MARK" "$VIDEO/mt-mark.png" 512

echo "==> @i tray (ai-tray.png)"
resize_square "$AI_TRAY" "$WEB/tray-icon.png" 44
resize_square "$AI_TRAY" "$APP_ASSETS/tray_icon.png" 44

echo "==> MT ligature (mt-ligature.png)"
resize_square "$LIGATURE" "$WEB/mt-ligature.png" 512
# Historical Flutter name — keep for zero Dart churn.
resize_square "$LIGATURE" "$APP_ASSETS/mt_mark_white_on_black.png" 512
resize_square "$LIGATURE" "$VIDEO/mt-ligature.png" 512

# Legacy MT tray was orphaned; do not regenerate it.
if [[ -f "$APP_ASSETS/mt_tray_icon.png" ]]; then
  echo "==> removing orphan app/assets/mt_tray_icon.png"
  rm -f "$APP_ASSETS/mt_tray_icon.png"
fi
if [[ -f "$WEB/mt-tray-icon.png" ]]; then
  echo "==> removing orphan web/public/brand/mt-tray-icon.png"
  rm -f "$WEB/mt-tray-icon.png"
fi

echo "==> macOS AppIcon (flutter_launcher_icons)"
(
  cd "$ROOT/app"
  dart run flutter_launcher_icons
)

echo ""
echo "Synced brand assets from brand/sources/."
echo "Next: rebuild Mac app; redeploy web if shipping /brand/."
echo "Optional CDN (landing-intro media only): ./scripts/upload-brand-r2.sh"
