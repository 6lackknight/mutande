/**
 * Public installers — alpha channel.
 * Binaries live in web/public/downloads/ (gitignored); copy before deploy.
 * Override URLs on Vercel with NEXT_PUBLIC_* if hosting moves off this site.
 */
export const MAC_DMG_CHANNEL =
  process.env.NEXT_PUBLIC_MAC_DMG_CHANNEL ?? "alpha";

export const MAC_DMG_VERSION =
  process.env.NEXT_PUBLIC_MAC_DMG_VERSION ?? "1.0.4";

/**
 * Apple Silicon — rolling public alias on the site.
 * Release script also writes mutande-alpha-arm64.dmg; alias is what prod ships.
 */
export const MAC_DMG_URL_ARM64 =
  process.env.NEXT_PUBLIC_MAC_DMG_URL_ARM64 ??
  "/downloads/mutande-alpha.dmg";

/** Intel (x86_64). Empty string = not published yet. */
export const MAC_DMG_URL_INTEL =
  process.env.NEXT_PUBLIC_MAC_DMG_URL_INTEL ??
  "/downloads/mutande-alpha-intel.dmg";

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
  "/downloads/mutande-alpha-windows.zip";

export const WIN_ZIP_PUBLISHED =
  process.env.NEXT_PUBLIC_WIN_ZIP_PUBLISHED === "1";

export const WIN_ZIP_LABEL = `mutande ${WIN_ZIP_VERSION} Windows (${WIN_ZIP_CHANNEL})`;
