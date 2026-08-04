/** Beat map @ 60fps — compose → text → thread → text → fan-out → text → hold. */
export const FPS = 60;
export const DURATION_SEC = 28;
export const DURATION_FRAMES = DURATION_SEC * FPS; // 1680

export const beats = {
  /** Claude Desktop — user types the intent */
  compose: { start: 0, end: 3.5 * FPS }, // 0–210
  /** kept as alias */
  intent: { start: 0, end: 3.5 * FPS },
  /** Big type: threads */
  explainThreads: { start: 3.5 * FPS, end: 5.75 * FPS }, // 210–345
  /** mutande thread + orb rail; replies/upvote drive pings */
  critique: { start: 5.75 * FPS, end: 14 * FPS }, // 345–840
  /** Big type: E2E (replaces weak final-doc hold) */
  explainE2E: { start: 14 * FPS, end: 16.25 * FPS }, // 840–975
  /** alias for any leftover finalDoc references */
  finalDoc: { start: 14 * FPS, end: 16.25 * FPS },
  transit: { start: 16.25 * FPS, end: 21.25 * FPS }, // 975–1275
  /** Big type: team agents */
  explainTeam: { start: 21.25 * FPS, end: 23.5 * FPS }, // 1275–1410
  hold: { start: 23.5 * FPS, end: DURATION_FRAMES }, // 1410–1680
} as const;

/** Full-bleed bold text cards — big type only. */
export const explainers = [
  {
    id: "threads",
    start: beats.explainThreads.start,
    end: beats.explainThreads.end,
    text: "secure collaboration threads for your agents",
  },
  {
    id: "e2e",
    start: beats.explainE2E.start,
    end: beats.explainE2E.end,
    text: "secure E2E by default",
  },
  {
    id: "team",
    start: beats.explainTeam.start,
    end: beats.explainTeam.end,
    text: "collaborate with your team's agents",
  },
] as const;

/**
 * Thread message / upvote moments — shared by CollaborationThread + AgentsBridge.
 * Spaced so each reply can land with a matching Claude↔ChatGPT ping.
 */
export const threadBeats = {
  claudeAsk: beats.critique.start + 18,
  chatgptReply: beats.critique.start + 150,
  claudeSeal: beats.critique.start + 300,
  upvote: beats.critique.start + 390,
} as const;

/** Three critique passes (message windows) — derived from threadBeats. */
export const critiquePasses = [
  { start: threadBeats.claudeAsk, end: threadBeats.chatgptReply },
  { start: threadBeats.chatgptReply, end: threadBeats.claudeSeal },
  { start: threadBeats.claudeSeal, end: beats.critique.end },
] as const;

/** Orb-rail packets — one per thread event, same frames. */
export const commPings = [
  {
    start: threadBeats.claudeAsk,
    end: threadBeats.claudeAsk + 42,
    dir: 0 as const,
    label: "critique?",
  },
  {
    start: threadBeats.chatgptReply,
    end: threadBeats.chatgptReply + 42,
    dir: 1 as const,
    label: "critique",
  },
  {
    start: threadBeats.claudeSeal,
    end: threadBeats.claudeSeal + 42,
    dir: 0 as const,
    label: "sealing",
  },
  {
    start: threadBeats.upvote,
    end: threadBeats.upvote + 48,
    dir: 1 as const,
    label: "▲ upvote",
  },
];

/** Already in Claude — ask ChatGPT to critique before seal/fan-out. */
export const DRAFT_FILENAME = "hacktoberfest-plan-wip.md";
export const COMPOSE_PROMPT =
  "ask @chatgpt to critique this before we send to the team";
