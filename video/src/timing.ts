/** Beat map @ 60fps — identity → compose → idea → route (+ seal) → fan-out → brand. */
export const FPS = 60;
export const DURATION_SEC = 28;
export const DURATION_FRAMES = DURATION_SEC * FPS; // 1680

export const beats = {
  /** Large address tree — the primitive */
  identity: { start: 0, end: 4.5 * FPS }, // 0–270
  /** Claude Desktop — ask an address */
  compose: { start: 4.5 * FPS, end: 9 * FPS }, // 270–540
  /** Full-bleed idea card */
  explain: { start: 9 * FPS, end: 11.5 * FPS }, // 540–690
  /** mutande thread — routing between identities (+ sealed transit as plumbing) */
  collab: { start: 11.5 * FPS, end: 18 * FPS }, // 690–1080
  /** aliases kept for older component imports */
  critique: { start: 11.5 * FPS, end: 18 * FPS },
  /** In-collab seal — subordinate, not its own scene */
  seal: { start: 16 * FPS, end: 18 * FPS }, // 960–1080
  /** Address fan-out — aha */
  fanout: { start: 18 * FPS, end: 24 * FPS }, // 1080–1440
  /** transit spans fan-out for EncryptedTransit */
  transit: { start: 18 * FPS, end: 24 * FPS },
  hold: { start: 24 * FPS, end: DURATION_FRAMES }, // 1440–1680
} as const;

/** Full-bleed bold type — one idea card. */
export const explainers = [
  {
    id: "address",
    start: beats.explain.start,
    end: beats.explain.end,
    text: "Every intelligence deserves an address.",
  },
] as const;

/**
 * Thread / route moments — shared by CollaborationThread + AddressRoute.
 */
export const threadBeats = {
  claudeAsk: beats.collab.start + 18,
  chatgptReply: beats.collab.start + 110,
  researchReply: beats.collab.start + 200,
  seal: beats.seal.start + 12,
} as const;

/** Three message windows — derived from threadBeats. */
export const critiquePasses = [
  { start: threadBeats.claudeAsk, end: threadBeats.chatgptReply },
  { start: threadBeats.chatgptReply, end: threadBeats.researchReply },
  { start: threadBeats.researchReply, end: beats.collab.end },
] as const;

/** Route hops — identity → identity (not model ping candy). */
export const routeHops = [
  {
    start: threadBeats.claudeAsk,
    end: threadBeats.claudeAsk + 48,
    from: "@claude",
    to: "@chatgpt",
  },
  {
    start: threadBeats.chatgptReply,
    end: threadBeats.chatgptReply + 48,
    from: "@chatgpt",
    to: "@research",
  },
  {
    start: threadBeats.researchReply,
    end: threadBeats.researchReply + 48,
    from: "@research",
    to: "@claude",
  },
] as const;

/** Kept for AgentsBridge if still mounted — maps to route hops. */
export const commPings = [
  {
    start: routeHops[0].start,
    end: routeHops[0].end,
    dir: 0 as const,
    label: "→ @chatgpt",
  },
  {
    start: routeHops[1].start,
    end: routeHops[1].end,
    dir: 1 as const,
    label: "→ @research",
  },
  {
    start: routeHops[2].start,
    end: routeHops[2].end,
    dir: 0 as const,
    label: "→ @claude",
  },
];

export const DRAFT_FILENAME = "q3-plan-wip.md";
export const COMPOSE_PROMPT =
  "Ask @research to critique this before we send it to the team.";

export const IDENTITY_HANDLE = "alice@salesco";
export const IDENTITY_AGENTS = ["/jarvis", "/research", "/review"] as const;
