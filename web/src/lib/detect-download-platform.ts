/**
 * Client-only OS/arch detection for the download page.
 *
 * Heuristic (in order):
 * 1. `navigator.userAgentData` + `getHighEntropyValues(['architecture'])`
 *    when available — authoritative `platform` + `architecture` (`arm` / `x86`).
 * 2. Else parse `navigator.userAgent` / `navigator.platform`:
 *    - Windows → windows
 *    - Mac → prefer silicon. Classic `navigator.platform === "MacIntel"` is
 *      unreliable (Apple Silicon Safari still reports MacIntel). Without
 *      userAgentData we cannot trust Intel vs ARM, so default Mac → silicon.
 *    - Explicit ARM signals in UA (`ARM64`, `aarch64`) → silicon.
 * 3. Non-desktop / unknown → silicon (always-published alpha).
 *
 * Callers should pass through {@link resolvePublishedPlatform} so unpublished
 * Intel/Windows builds fall back to the next available card.
 */

export type DownloadPlatform = "mac_arm64" | "mac_intel" | "windows";

type UAData = {
  platform?: string;
  getHighEntropyValues?: (
    hints: string[],
  ) => Promise<{ platform?: string; architecture?: string }>;
};

function isWindows(platform: string, ua: string): boolean {
  return /Win/i.test(platform) || /Windows/i.test(ua);
}

function isMac(platform: string, ua: string): boolean {
  return /Mac/i.test(platform) || /Mac OS X|Macintosh/i.test(ua);
}

function archFromHint(architecture: string | undefined): "arm" | "x86" | null {
  if (!architecture) return null;
  const a = architecture.toLowerCase();
  if (a.includes("arm") || a === "aarch64") return "arm";
  if (a.includes("x86") || a.includes("amd64") || a === "ia32") return "x86";
  return null;
}

/** Sync fallback when userAgentData / high-entropy values are unavailable. */
export function detectDownloadPlatformSync(): DownloadPlatform {
  if (typeof navigator === "undefined") return "mac_arm64";

  const ua = navigator.userAgent ?? "";
  const platform = navigator.platform ?? "";

  if (isWindows(platform, ua)) return "windows";

  if (isMac(platform, ua)) {
    // Rare but useful: some Chromium builds expose ARM in the UA string.
    if (/ARM64|aarch64|Apple Silicon/i.test(ua)) return "mac_arm64";
    // MacIntel is reported on both Intel and Apple Silicon — prefer silicon.
    return "mac_arm64";
  }

  return "mac_arm64";
}

/**
 * Async detection preferring Client Hints architecture when the browser
 * supports it (Chrome/Edge). Falls back to {@link detectDownloadPlatformSync}.
 */
export async function detectDownloadPlatform(): Promise<DownloadPlatform> {
  if (typeof navigator === "undefined") return "mac_arm64";

  const uaData = (
    navigator as Navigator & { userAgentData?: UAData }
  ).userAgentData;

  if (uaData?.getHighEntropyValues) {
    try {
      const { platform, architecture } = await uaData.getHighEntropyValues([
        "architecture",
        "platform",
      ]);
      const plat = platform || uaData.platform || "";
      const arch = archFromHint(architecture);

      if (/Win/i.test(plat)) return "windows";
      if (/macOS|Mac/i.test(plat)) {
        if (arch === "x86") return "mac_intel";
        // arm or unknown Mac architecture → silicon
        return "mac_arm64";
      }
    } catch {
      // Permissions / unsupported — fall through
    }
  }

  // Some browsers expose platform on userAgentData without high-entropy arch.
  if (uaData?.platform) {
    if (/Win/i.test(uaData.platform)) return "windows";
    if (/macOS|Mac/i.test(uaData.platform)) return "mac_arm64";
  }

  return detectDownloadPlatformSync();
}

/** Prefer detected platform when published; else next best available. */
export function resolvePublishedPlatform(
  detected: DownloadPlatform,
  available: readonly DownloadPlatform[],
): DownloadPlatform {
  if (available.includes(detected)) return detected;
  // Fallback order: silicon → intel → windows (first published in this list).
  const preference: DownloadPlatform[] = ["mac_arm64", "mac_intel", "windows"];
  for (const p of preference) {
    if (available.includes(p)) return p;
  }
  return "mac_arm64";
}
