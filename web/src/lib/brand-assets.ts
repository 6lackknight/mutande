/**
 * Public marketing media on Cloudflare R2 (`mutande-releases`).
 *
 * Same origin as installers (NEXT_PUBLIC_DOWNLOADS_BASE). Upload with:
 *   ./scripts/upload-brand-r2.sh
 *
 * Relative `/brand/…` fallbacks are local-dev only (files under web/public/brand).
 */

const ASSETS_BASE = (
  process.env.NEXT_PUBLIC_BRAND_ASSETS_BASE ??
  process.env.NEXT_PUBLIC_DOWNLOADS_BASE ??
  "https://downloads.mutande.online"
).replace(/\/$/, "");

function brandUrl(fileName: string, localPath: string): string {
  if (process.env.NEXT_PUBLIC_BRAND_ASSETS_LOCAL === "1") {
    return localPath;
  }
  if (ASSETS_BASE) {
    return `${ASSETS_BASE}/brand/${fileName}`;
  }
  return localPath;
}

export const LANDING_INTRO_POSTER_URL = brandUrl(
  "landing-intro-poster.png",
  "/brand/landing-intro-poster.png",
);

export const LANDING_INTRO_WEBM_URL = brandUrl(
  "landing-intro.webm",
  "/brand/landing-intro.webm",
);

export const LANDING_INTRO_MP4_URL = brandUrl(
  "landing-intro.mp4",
  "/brand/landing-intro.mp4",
);
