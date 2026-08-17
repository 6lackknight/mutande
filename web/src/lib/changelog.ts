/**
 * Customer-facing desktop alpha notes for /changelog and the download page.
 * User-visible changes only — no internal tooling, infra, or implementation detail.
 *
 * --- unreleased (internal; fold into next cut or discard) ---
 * Mixpanel desktop funnel (v1.1.4) stays internal until privacy copy discloses analytics.
 */

export type ChangelogEntry = {
  version: string;
  date: string;
  title: string;
  notes: string[];
};

export const CHANGELOG: ChangelogEntry[] = [
  {
    version: "2.0.4",
    date: "2026-08-17",
    title: "Collab dashboard & updates",
    notes: [
      "Collab home dashboard with project dossiers, activity, and a shared brain pane.",
      "Manage collab members, agent roster, and archive from the Mac app.",
      "Notifications panel shows recent inbox banners; tap to open the thread.",
      "App prompts you to reinstall when you're behind the published alpha.",
      "Improved crash and error reporting for faster fixes during alpha.",
    ],
  },
  {
    version: "2.0.1",
    date: "2026-08-16",
    title: "Collab on Windows",
    notes: [
      "Collab boards and cards work on the Windows alpha.",
      "Stability fixes for collab sync on desktop.",
    ],
  },
  {
    version: "2.0.0",
    date: "2026-08-16",
    title: "Collab",
    notes: [
      "New Collab tab: kanban boards where each card is a thread.",
      "Create collabs with steerers, agents, and standing instructions.",
      "Collab threads still appear in Threads with Collab / Unfiled filters.",
      "Agents can list boards, open cards, move lanes, and add learnings via MCP.",
    ],
  },
  {
    version: "1.1.4",
    date: "2026-08-13",
    title: "Network & reading layout",
    notes: [
      "Network shows org teammates and external contacts; tap someone to see destinations and start a thread.",
      "Threads reading uses a resizable split with a sidebar inspector.",
    ],
  },
  {
    version: "1.1.3",
    date: "2026-08-12",
    title: "Windows sign-in fix",
    notes: [
      "Windows Sign in opens the full browser login page again.",
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
      "Network tab: browse Me, your org, and external contacts to see how mail routes.",
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
      "Windows alpha ships as an installer alongside Mac.",
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
    title: "Download & join polish",
    notes: [
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
    date: "2026-08-04",
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
      "Clearer agent addresses and routing in Network.",
    ],
  },
];

export const LATEST_CHANGELOG = CHANGELOG[0];
