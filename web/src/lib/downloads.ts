/**
 * Public installers — alpha channel on Cloudflare R2 (`mutande-releases`).
 *
 * Set NEXT_PUBLIC_DOWNLOADS_BASE to the public origin (no trailing slash), e.g.
 *   https://downloads.mutande.online
 * Upload with: ./scripts/upload-downloads-r2.sh
 *
 * Relative `/downloads/…` fallbacks are local-dev only (gitignored copies).
 */

const DOWNLOADS_BASE = (
  process.env.NEXT_PUBLIC_DOWNLOADS_BASE ??
  "https://downloads.mutande.online"
).replace(/\/$/, "");

function installerUrl(fileName: string, legacyPath: string): string {
  if (DOWNLOADS_BASE) {
    return `${DOWNLOADS_BASE}/${fileName}`;
  }
  return legacyPath;
}

export const MAC_DMG_CHANNEL =
  process.env.NEXT_PUBLIC_MAC_DMG_CHANNEL ?? "alpha";

export const MAC_DMG_VERSION =
  process.env.NEXT_PUBLIC_MAC_DMG_VERSION ?? "1.0.5";

/**
 * Apple Silicon — rolling public alias.
 * Release script also writes mutande-alpha-arm64.dmg; alias is what we publish.
 */
export const MAC_DMG_URL_ARM64 =
  process.env.NEXT_PUBLIC_MAC_DMG_URL_ARM64 ??
  installerUrl("mutande-alpha.dmg", "/downloads/mutande-alpha.dmg");

/** Intel (x86_64). */
export const MAC_DMG_URL_INTEL =
  process.env.NEXT_PUBLIC_MAC_DMG_URL_INTEL ??
  installerUrl(
    "mutande-alpha-intel.dmg",
    "/downloads/mutande-alpha-intel.dmg",
  );

export const MAC_INTEL_PUBLISHED =
  process.env.NEXT_PUBLIC_MAC_INTEL_PUBLISHED === "1";

/** @deprecated Prefer MAC_DMG_URL_ARM64. */
export const MAC_DMG_URL =
  process.env.NEXT_PUBLIC_MAC_DMG_URL ?? MAC_DMG_URL_ARM64;

export const MAC_DMG_LABEL = `mutande ${MAC_DMG_VERSION} (${MAC_DMG_CHANNEL})`;

/** Unsigned Windows portable zip (SmartScreen may warn). */
export const WIN_ZIP_CHANNEL =
  process.env.NEXT_PUBLIC_WIN_ZIP_CHANNEL ?? MAC_DMG_CHANNEL;

export const WIN_ZIP_VERSION =
  process.env.NEXT_PUBLIC_WIN_ZIP_VERSION ?? MAC_DMG_VERSION;

export const WIN_ZIP_URL =
  process.env.NEXT_PUBLIC_WIN_ZIP_URL ??
  installerUrl(
    "mutande-alpha-windows.zip",
    "/downloads/mutande-alpha-windows.zip",
  );

export const WIN_ZIP_PUBLISHED =
  process.env.NEXT_PUBLIC_WIN_ZIP_PUBLISHED === "1";

export const WIN_ZIP_LABEL = `mutande ${WIN_ZIP_VERSION} Windows (${WIN_ZIP_CHANNEL})`;
