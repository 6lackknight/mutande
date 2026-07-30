/** Beat map @ 60fps — compose typing scene + cinematic handoff. */
export const FPS = 60;
export const DURATION_SEC = 24;
export const DURATION_FRAMES = DURATION_SEC * FPS; // 1440

export const beats = {
  /** macOS window — user types the intent */
  compose: { start: 0, end: 4 * FPS }, // 0–240
  /** kept as alias for compose end → critique start */
  intent: { start: 0, end: 4 * FPS },
  critique: { start: 4 * FPS, end: 11 * FPS }, // 240–660
  finalDoc: { start: 11 * FPS, end: 14 * FPS }, // 660–840
  transit: { start: 14 * FPS, end: 19 * FPS }, // 840–1140
  hold: { start: 19 * FPS, end: DURATION_FRAMES }, // 1140–1440
} as const;

/** Three critique passes inside the critique window. */
export const critiquePasses = [
  { start: beats.critique.start, end: beats.critique.start + 140 },
  { start: beats.critique.start + 140, end: beats.critique.start + 280 },
  { start: beats.critique.start + 280, end: beats.critique.end },
] as const;

/** Already in Claude — ask ChatGPT to critique before seal/fan-out. */
export const DRAFT_FILENAME = "hacktoberfest-plan-wip.md";
export const COMPOSE_PROMPT =
  "ask @chatgpt to critique this before we send to the team";
