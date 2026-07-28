/**
 * Public Mac installer (alpha channel — single rolling artifact).
 * Override on Vercel with NEXT_PUBLIC_MAC_DMG_URL if hosting moves off this site.
 */
export const MAC_DMG_CHANNEL =
  process.env.NEXT_PUBLIC_MAC_DMG_CHANNEL ?? "alpha";

export const MAC_DMG_URL =
  process.env.NEXT_PUBLIC_MAC_DMG_URL ?? "/downloads/mutande-alpha.dmg";

export const MAC_DMG_VERSION =
  process.env.NEXT_PUBLIC_MAC_DMG_VERSION ?? "1.0.2";

export const MAC_DMG_LABEL = `mutande ${MAC_DMG_VERSION} (${MAC_DMG_CHANNEL})`;
