/** Beat map @ 60fps — identity → idea → compose → idea → route → fan-out → idea → brand. */
export const FPS = 60;
export const DURATION_SEC = 28;
export const DURATION_FRAMES = DURATION_SEC * FPS; // 1680

export const beats = {
  /** Large address tree — the primitive */
  identity: { start: 0, end: 3.5 * FPS }, // 0–210
  /** Claude Desktop — ask an address */
  compose: { start: 5.7 * FPS, end: 9.5 * FPS }, // 342–570
  /** mutande thread — routing between identities (+ sealed transit as plumbing) */
  collab: { start: 11.7 * FPS, end: 17.2 * FPS }, // 702–1032
  /** aliases kept for older component imports */
  critique: { start: 11.7 * FPS, end: 17.2 * FPS },
  /** In-collab seal — subordinate, not its own scene */
  seal: { start: 15.7 * FPS, end: 17.2 * FPS }, // 942–1032
  /** Address fan-out — aha */
  fanout: { start: 17.2 * FPS, end: 21.8 * FPS }, // 1032–1308
  /** transit spans fan-out for EncryptedTransit */
  transit: { start: 17.2 * FPS, end: 21.8 * FPS },
  hold: { start: 24.3 * FPS, end: DURATION_FRAMES }, // 1458–1680
} as const;

/**
 * Three Apple-style full-bleed lines — the only on-screen copy that teaches.
 * Visual beats prove each line; crypto stays plumbing.
 */
export const explainers = [
  {
    id: "address",
    start: 3.5 * FPS,
    end: 5.7 * FPS,
    text: "An address for every intelligence.",
  },
  {
    id: "send",
    start: 9.5 * FPS,
    end: 11.7 * FPS,
    text: "Send work to who should do it.",
  },
  {
    id: "team",
    start: 21.8 * FPS,
    end: 24.3 * FPS,
    text: "One message.\nThe whole team.",
  },
] as const;

/**
 * Thread / route moments — shared by CollaborationThread + AddressRoute.
 */
export const threadBeats = {
  claudeAsk: beats.collab.start + 18,
  chatgptReply: beats.collab.start + 100,
  researchReply: beats.collab.start + 190,
  seal: beats.seal.start + 12,
} as const;

/** Three message windows — derived from threadBeats. */
export const critiquePasses = [
  { start: threadBeats.claudeAsk, end: threadBeats.chatgptReply },
  { start: threadBeats.chatgptReply, end: threadBeats.researchReply },
  { start: threadBeats.researchReply, end: beats.collab.end },
] as const;

/** Route hops — same cast as opening participants stack. */
export const routeHops = [
  {
    start: threadBeats.claudeAsk,
    end: threadBeats.claudeAsk + 48,
    from: "@cursor",
    to: "@claude",
  },
  {
    start: threadBeats.chatgptReply,
    end: threadBeats.chatgptReply + 48,
    from: "@claude",
    to: "bob@acme/openclaw",
  },
  {
    start: threadBeats.researchReply,
    end: threadBeats.researchReply + 48,
    from: "bob@acme/openclaw",
    to: "alice@acme/n8n-tickets",
  },
] as const;

/** Kept for AgentsBridge if still mounted — maps to route hops. */
export const commPings = [
  {
    start: routeHops[0].start,
    end: routeHops[0].end,
    dir: 0 as const,
    label: "→ @claude",
  },
  {
    start: routeHops[1].start,
    end: routeHops[1].end,
    dir: 1 as const,
    label: "→ bob@acme/openclaw",
  },
  {
    start: routeHops[2].start,
    end: routeHops[2].end,
    dir: 0 as const,
    label: "→ alice@acme/n8n-tickets",
  },
];

export const DRAFT_FILENAME = "q3-plan-wip.md";
/** Highlighted address must match COMPOSE_HIGHLIGHT. */
export const COMPOSE_PROMPT =
  "Ask bob@acme/openclaw to critique this before we send it to the team.";
export const COMPOSE_HIGHLIGHT = "bob@acme/openclaw";

/** @deprecated — opening uses PARTICIPANTS stack; kept for stray imports. */
export const IDENTITY_HANDLE = "@cursor";
export const IDENTITY_AGENTS = [
  "@claude",
  "bob@acme/openclaw",
  "alice@acme/n8n-tickets",
] as const;
