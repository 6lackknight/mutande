import { Easing, interpolate } from "remotion";
import { beats } from "./timing";

export type CameraPose = {
  scale: number;
  x: number;
  y: number;
};

const ease = Easing.bezier(0.4, 0, 0.2, 1);

/** Three signature motions: identity breathe-in, collab hold, fan-out pull-wide. */
export const getCameraPose = (frame: number): CameraPose => {
  // Identity — slow absorb
  if (frame < beats.identity.end) {
    const t = interpolate(frame, [0, 50], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: ease,
    });
    const breathe = 1 + Math.sin(frame * 0.028) * 0.006;
    return {
      scale: interpolate(t, [0, 1], [1.04, 1.1]) * breathe,
      x: 0,
      y: interpolate(t, [0, 1], [1.5, 0]),
    };
  }

  // Compose — soft push on the host window
  if (frame < beats.compose.end) {
    const t = interpolate(
      frame,
      [beats.compose.start, beats.compose.start + 40],
      [0, 1],
      { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease },
    );
    return {
      scale: interpolate(t, [0, 1], [1.06, 1.12]),
      x: 0,
      y: 0,
    };
  }

  // Explainer — flat
  if (frame < beats.collab.start) {
    return { scale: 1.02, x: 0, y: 0 };
  }

  // Collaboration — hold / slight breathe (includes in-thread seal)
  if (frame < beats.fanout.start) {
    const t = interpolate(
      frame,
      [beats.collab.start, beats.collab.start + 36],
      [0, 1],
      { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease },
    );
    const breathe = 1 + Math.sin((frame - beats.collab.start) * 0.03) * 0.007;
    return {
      scale: interpolate(t, [0, 1], [1.04, 1.14]) * breathe,
      x: 0,
      y: -0.5,
    };
  }

  // Fan-out — pull wide
  if (frame < beats.hold.start) {
    const t = interpolate(
      frame,
      [beats.fanout.start, beats.fanout.start + 48],
      [0, 1],
      { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease },
    );
    return {
      scale: interpolate(t, [0, 1], [1.08, 0.96]),
      x: 0,
      y: 0,
    };
  }

  return { scale: 1, x: 0, y: 0 };
};
