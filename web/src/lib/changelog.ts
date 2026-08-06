/**
 * Product-facing desktop alpha notes for /changelog and the download page.
 * Keep entries short; prefer themes from release cuts over git-log dumps.
 */

export type ChangelogEntry = {
  version: string;
  date: string;
  title: string;
  notes: string[];
};

export const CHANGELOG: ChangelogEntry[] = [
  {
    version: "1.0.10",
    date: "2026-08-06",
    title: "Restart courier & version mismatch",
    notes: [
      "Settings Restart courier clears a stuck or stale mutande-core sidecar without resetting onboarding.",
      "Detects app vs daemon version mismatch so a leftover core binary no longer blocks the desktop.",
    ],
  },
  {
    version: "1.0.9",
    date: "2026-08-06",
    title: "Attachments & host connect",
    notes: [
      "Thread reading pane shows file attachments with in-app preview for common types.",
      "Hardened AI host connect (MCP + skill) and Settings host-link status.",
      "Hub device registration / store updates for multi-device wrap targets.",
    ],
  },
  {
    version: "1.0.8",
    date: "2026-08-05",
    title: "Courier fixes & landing refresh",
    notes: [
      "Daemon RPC and hub store fixes ahead of the next desktop cut.",
      "Refreshed Address Intelligence landing intro video and poster.",
    ],
  },
  {
    version: "1.0.7",
    date: "2026-08-05",
    title: "One-shot Mac + Windows release",
    notes: [
      "Single release-desktop path: notarized Mac DMGs, Windows zip, downloads CDN, site redeploy.",
      "Join UI polish and tighter Auth0 membership checks.",
      "Auth0 sign-out and clearer onboarding error handling.",
    ],
  },
  {
    version: "1.0.6",
    date: "2026-08-05",
    title: "Onboarding & Mac release hardening",
    notes: [
      "Skip create/join when the account already has a team (e.g. finished on the web).",
      "Mac DMG release script verifies a real Flutter binary before reusing a build tree.",
      "Windows CI build fixes for the unsigned alpha zip.",
    ],
  },
  {
    version: "1.0.5",
    date: "2026-08-05",
    title: "Host skill, notifications, Windows on CDN",
    notes: [
      "Two-step Connect AI hosts flow: MCP, then skill install.",
      "Local inbox notifications with mute and Settings → Notifications.",
      "Windows alpha zip published to downloads.mutande.online alongside Mac DMGs.",
      "Mac Release notification delegate fix for menu-bar banners.",
    ],
  },
  {
    version: "1.0.4",
    date: "2026-08-04",
    title: "Site & login polish",
    notes: [
      "Landing footer visibility tweak for smaller viewports.",
      "Clearer invite-code copy on sign-in.",
    ],
  },
  {
    version: "1.0.3",
    date: "2026-08-04",
    title: "Windows shell & Mac chrome",
    notes: [
      "First Windows alpha app shell (portable zip via Actions).",
      "In-app feedback from Settings; Threads reading UI refresh.",
      "Short dark welcome splash with the working orb on Mac launch.",
    ],
  },
  {
    version: "1.0.2",
    date: "2026-07-28",
    title: "Rolling alpha downloads",
    notes: [
      "Public installers use a rolling alpha channel on the downloads CDN.",
      "Mac DMGs ship as mutande-alpha.dmg (Silicon) and mutande-alpha-intel.dmg.",
    ],
  },
  {
    version: "1.0.1",
    date: "2026-07-28",
    title: "Host picker & agent routing",
    notes: [
      "Connect hosts one at a time via picker with consistent host icons.",
      "Agents & routing improvements; notarized Mac DMG release path hardening.",
    ],
  },
];

export const LATEST_CHANGELOG = CHANGELOG[0];
