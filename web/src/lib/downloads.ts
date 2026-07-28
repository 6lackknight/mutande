/**
 * Public Mac installer.
 * Default: same-origin static file under web/public/downloads (deployed with the site).
 * Override on Vercel with NEXT_PUBLIC_MAC_DMG_URL (e.g. R2 / GitHub Releases).
 */
export const MAC_DMG_URL =
  process.env.NEXT_PUBLIC_MAC_DMG_URL ?? "/downloads/mutande-latest.dmg";

export const MAC_DMG_VERSION =
  process.env.NEXT_PUBLIC_MAC_DMG_VERSION ?? "1.0.1";
