import { Easing, interpolate } from "remotion";
import { beats } from "./timing";

export type CameraPose = {
  scale: number;
  x: number;
  y: number;
};

const ease = Easing.bezier(0.4, 0, 0.2, 1);

/** Piecewise cinematic camera — product beats only; explainers are flat overlays. */
export const getCameraPose = (frame: number): CameraPose => {
  // Compose
  if (frame < beats.compose.end - 24) {
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

  // Into first explainer / out of compose — hold neutral
  if (frame < beats.critique.start) {
    return { scale: 1.05, x: 0, y: 0 };
  }

  // Thread stage enter
  if (frame < beats.critique.start + 48) {
    const t = interpolate(
      frame,
      [beats.critique.start, beats.critique.start + 40],
      [0, 1],
      { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease },
    );
    return {
      scale: interpolate(t, [0, 1], [1.05, 1.18]),
      x: 0,
      y: interpolate(t, [0, 1], [0, -1]),
    };
  }

  // Collaboration
  if (frame < beats.explainE2E.start) {
    const breathe = 1 + Math.sin((frame - beats.critique.start) * 0.03) * 0.008;
    return {
      scale: 1.18 * breathe,
      x: 0,
      y: -1,
    };
  }

  // E2E text — flatten
  if (frame < beats.transit.start) {
    return { scale: 1.04, x: 0, y: 0 };
  }

  // Transit / fan-out wide
  if (frame < beats.explainTeam.start) {
    const t = interpolate(
      frame,
      [beats.transit.start, beats.transit.start + 55],
      [0, 1],
      { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease },
    );
    return {
      scale: interpolate(t, [0, 1], [1.2, 1.0]),
      x: 0,
      y: interpolate(t, [0, 1], [4, 0]),
    };
  }

  return { scale: 1, x: 0, y: 0 };
};
