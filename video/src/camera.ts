import { Easing, interpolate } from "remotion";
import { beats } from "./timing";

export type CameraPose = {
  scale: number;
  x: number;
  y: number;
};

const ease = Easing.bezier(0.4, 0, 0.2, 1);

/** Piecewise cinematic camera — compose → collaboration thread → fan-out. */
export const getCameraPose = (frame: number): CameraPose => {
  // Compose: settle on the typing window
  if (frame < beats.compose.end - 40) {
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

  // Compose → collaboration: gentle push into the thread (not extreme)
  if (frame < beats.critique.start + 40) {
    const t = interpolate(
      frame,
      [beats.compose.end - 40, beats.critique.start + 36],
      [0, 1],
      { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease },
    );
    return {
      scale: interpolate(t, [0, 1], [1.12, 1.28]),
      x: 0,
      y: interpolate(t, [0, 1], [0, -2]),
    };
  }

  // Collaboration thread: hold moderate zoom, slight breathe
  if (frame < beats.finalDoc.start) {
    const breathe = 1 + Math.sin((frame - beats.critique.start) * 0.035) * 0.01;
    return {
      scale: 1.28 * breathe,
      x: 0,
      y: -2,
    };
  }

  // Final doc
  if (frame < beats.transit.start) {
    const t = interpolate(
      frame,
      [beats.finalDoc.start, beats.finalDoc.start + 50],
      [0, 1],
      { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease },
    );
    return {
      scale: interpolate(t, [0, 1], [1.28, 1.35]),
      x: 0,
      y: interpolate(t, [0, 1], [-2, 8]),
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
      scale: interpolate(t, [0, 1], [1.35, 1.0]),
      x: 0,
      y: interpolate(t, [0, 1], [8, 0]),
    };
  }

  return { scale: 1, x: 0, y: 0 };
};
