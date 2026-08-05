import React from "react";
import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { colors, FONT } from "../theme";

type Props = {
  text: string;
  start: number;
  end: number;
};

/** Full-bleed big bold type — no chrome, no icons. */
export const ExplainerCard: React.FC<Props> = ({ text, start, end }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (frame < start - 2 || frame > end + 2) return null;

  const enter = spring({
    frame: Math.max(0, frame - start),
    fps,
    config: { damping: 18, stiffness: 120 },
    durationInFrames: 28,
  });
  const fadeOut = interpolate(frame, [end - 18, end], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const fadeIn = interpolate(frame, [start, start + 10], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const opacity = fadeIn * fadeOut * Math.min(1, enter + 0.15);
  const y = (1 - enter) * 28;
  const scale = 0.96 + enter * 0.04;

  return (
    <AbsoluteFill
      style={{
        justifyContent: "center",
        alignItems: "center",
        padding: "0 72px",
        opacity,
        zIndex: 8,
        pointerEvents: "none",
        fontFamily: FONT,
      }}
    >
      <div
        style={{
          maxWidth: 860,
          textAlign: "center",
          transform: `translateY(${y}px) scale(${scale})`,
          fontSize: 64,
          fontWeight: 700,
          lineHeight: 1.1,
          letterSpacing: "-0.045em",
          color: colors.stone900,
        }}
      >
        {text}
      </div>
    </AbsoluteFill>
  );
};
