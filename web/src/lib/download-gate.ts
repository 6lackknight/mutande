import { cookies } from "next/headers";

/** Set after a successful waitlist POST. UI gate only — R2 URLs stay public. */
export const DOWNLOAD_UNLOCK_COOKIE = "mutande_alpha_ok";

const MAX_AGE_SEC = 60 * 60 * 24 * 365;

export function downloadUnlockCookieOptions() {
  return {
    httpOnly: true,
    sameSite: "lax" as const,
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: MAX_AGE_SEC,
  };
}

export async function hasDownloadUnlock(): Promise<boolean> {
  const jar = await cookies();
  return jar.get(DOWNLOAD_UNLOCK_COOKIE)?.value === "1";
}

/** Only `/download` is a valid post-waitlist next — no open redirects. */
export function downloadNextFromSearch(
  next: string | undefined,
): "/download" | null {
  return next === "/download" || next === "download" ? "/download" : null;
}
