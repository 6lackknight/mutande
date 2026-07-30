import { Easing, interpolate } from "remotion";
import { beats } from "./timing";

export type CameraPose = {
  scale: number;
  x: number;
  y: number;
};

const ease = Easing.bezier(0.4, 0, 0.2, 1);

/** Piecewise cinematic camera — compose → threaded collab → fan-out. */
export const getCameraPose = (frame: number): CameraPose => {
  // Compose: settle on the typing window
  if (frame < beats.compose.end - 36) {
    const t = interpolate(frame, [0, 40], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: ease,
    });
    return {
      scale: interpolate(t, [0, 1], [1.08, 1.12]),
      x: 0,
      y: interpolate(t, [0, 1], [2, 0]),
    };
  }

  // Compose → thread stage
  if (frame < beats.critique.start + 48) {
    const t = interpolate(
      frame,
      [beats.compose.end - 36, beats.critique.start + 36],
      [0, 1],
      { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease },
    );
    return {
      scale: interpolate(t, [0, 1], [1.12, 1.18]),
      x: 0,
      y: interpolate(t, [0, 1], [0, -1]),
    };
  }

  // Collaboration — hold on rail + thread while replies / upvote fire
  if (frame < beats.finalDoc.start) {
    const breathe = 1 + Math.sin((frame - beats.critique.start) * 0.03) * 0.008;
    return {
      scale: 1.18 * breathe,
      x: 0,
      y: -1,
    };
  }

  // Final doc
  if (frame < beats.transit.start) {
    const t = interpolate(
      frame,
      [beats.finalDoc.start, beats.finalDoc.start + 40],
      [0, 1],
      { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease },
    );
    return {
      scale: interpolate(t, [0, 1], [1.18, 1.32]),
      x: 0,
      y: interpolate(t, [0, 1], [-1, 6]),
    };
  }

  // Transit / fan-out wide
  if (frame < beats.hold.start) {
    const t = interpolate(
      frame,
      [beats.transit.start, beats.transit.start + 55],
      [0, 1],
      { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease },
    );
    return {
      scale: interpolate(t, [0, 1], [1.32, 1.0]),
      x: 0,
      y: interpolate(t, [0, 1], [6, 0]),
    };
  }

  return { scale: 1, x: 0, y: 0 };
};
