/**
 * Customer-facing desktop alpha notes for /changelog and the download page.
 * User-visible changes only — no internal tooling, infra, or implementation detail.
 *
 * --- unreleased (internal; fold into next cut or discard) ---
 * v1.1.4+ (2026-08-13): Mixpanel on Mac/Windows desktop — onboarding funnel
 * (sign-in, create/join, connect host, ping wizard, home). Web identify wired
 * so same Auth0 account stitches web ↔ desktop in Mixpanel (Auth0 sub only;
 * no email/handle in events). Not user-facing — no changelog bullet unless we
 * disclose analytics in privacy copy first.
 */

export type ChangelogEntry = {
  version: string;
  date: string;
  title: string;
  notes: string[];
};

export const CHANGELOG: ChangelogEntry[] = [
  {
    version: "1.1.3",
    date: "2026-08-12",
    title: "Windows sign-in fix",
    notes: [
      "Windows Sign in opens the full Auth0 login URL again (browser was dropping parameters).",
    ],
  },
  {
    version: "1.1.2",
    date: "2026-08-12",
    title: "Icons & multi-device mail",
    notes: [
      "Sharper @i app and menu bar icons.",
      "More reliable sending when the same device was registered more than once.",
    ],
  },
  {
    version: "1.1.1",
    date: "2026-08-11",
    title: "Refreshed logo",
    notes: [
      "Updated @i mark across the Mac app, menu bar, and website.",
    ],
  },
  {
    version: "1.1.0",
    date: "2026-08-11",
    title: "Network & external contacts",
    notes: [
      "Network tab: zoom between Me, your org, and external contacts to see how mail routes.",
      "Add external contacts with a pairing PIN; warnings when a thread is no longer end-to-end encrypted.",
      "Compose moved to the toolbar; clearer Needs you labels in the thread list.",
    ],
  },
  {
    version: "1.0.12",
    date: "2026-08-07",
    title: "Version sync",
    notes: [
      "App and background courier stay matched — reinstall from Download if Restart courier reports a mismatch.",
      "Clearer Settings guidance when a fresh install is needed to pick up an update.",
    ],
  },
  {
    version: "1.0.11",
    date: "2026-08-07",
    title: "Stability & Windows installer",
    notes: [
      "Improved crash and error reporting for faster fixes during alpha.",
      "Windows alpha now ships as an installer alongside Mac.",
    ],
  },
  {
    version: "1.0.10",
    date: "2026-08-06",
    title: "Restart courier",
    notes: [
      "Restart courier in Settings clears a stuck background service without resetting your account.",
      "Detects version mismatches so an outdated courier no longer blocks the app.",
    ],
  },
  {
    version: "1.0.9",
    date: "2026-08-06",
    title: "Attachments & host connect",
    notes: [
      "View file attachments in threads with in-app preview for common types.",
      "More reliable Connect AI hosts flow and clearer connection status in Settings.",
      "Better support when you use mutande on more than one device.",
    ],
  },
  {
    version: "1.0.8",
    date: "2026-08-05",
    title: "Sync fixes & landing refresh",
    notes: [
      "Stability fixes for background sync.",
      "Refreshed Address Intelligence intro on the website.",
    ],
  },
  {
    version: "1.0.7",
    date: "2026-08-05",
    title: "Mac & Windows alpha",
    notes: [
      "Mac and Windows alphas available from Download.",
      "Smoother join flow if you already have a team from the web.",
      "Clearer sign-out and onboarding error messages.",
    ],
  },
  {
    version: "1.0.6",
    date: "2026-08-05",
    title: "Onboarding polish",
    notes: [
      "Skip create/join when your account already belongs to a team.",
      "More reliable Mac and Windows alpha installers.",
    ],
  },
  {
    version: "1.0.5",
    date: "2026-08-05",
    title: "Notifications & Windows",
    notes: [
      "Connect AI hosts in two steps: link the host, then install the collaboration skill.",
      "Local inbox notifications with mute controls in Settings.",
      "Windows alpha available alongside Mac.",
      "Fix for menu-bar notification banners on Mac.",
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
    title: "Windows & Mac polish",
    notes: [
      "First Windows alpha app.",
      "Send feedback from Settings; refreshed Threads reading view.",
      "Short welcome splash on Mac launch.",
    ],
  },
  {
    version: "1.0.2",
    date: "2026-07-28",
    title: "Rolling alpha downloads",
    notes: [
      "Download page offers the latest alpha builds for Mac (Apple Silicon and Intel).",
    ],
  },
  {
    version: "1.0.1",
    date: "2026-07-28",
    title: "Host picker & routing",
    notes: [
      "Connect AI hosts one at a time with a clearer picker.",
      "Agents and routing improvements.",
    ],
  },
];

export const LATEST_CHANGELOG = CHANGELOG[0];
