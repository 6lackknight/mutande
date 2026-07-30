/** Beat map @ 60fps — compose → threaded collab → fan-out. */
export const FPS = 60;
export const DURATION_SEC = 26;
export const DURATION_FRAMES = DURATION_SEC * FPS; // 1560

export const beats = {
  /** Claude Desktop — user types the intent */
  compose: { start: 0, end: 4 * FPS }, // 0–240
  /** kept as alias */
  intent: { start: 0, end: 4 * FPS },
  /** mutande thread + orb rail; replies/upvote drive pings */
  critique: { start: 4 * FPS, end: 14.5 * FPS }, // 240–870
  finalDoc: { start: 14.5 * FPS, end: 17 * FPS }, // 870–1020
  transit: { start: 17 * FPS, end: 22 * FPS }, // 1020–1320
  hold: { start: 22 * FPS, end: DURATION_FRAMES }, // 1320–1560
} as const;

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
