import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { colors, FONT } from "../theme";
import { COMPOSE_HIGHLIGHT, COMPOSE_PROMPT } from "../timing";

type Props = {
  appearFrame?: number;
};

/** Fallback chip — mirrors compose prompt (already in Claude). */
export const IntentChip: React.FC<Props> = ({ appearFrame = 0 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - appearFrame;
  const enter = spring({
    frame: local,
    fps,
    config: { damping: 16, stiffness: 110 },
  });
  const exit = interpolate(local, [150, 180], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const opacity = enter * exit;

  return (
    <div
      style={{
        position: "relative",
        maxWidth: 520,
        padding: "16px 22px",
        borderRadius: "22px 22px 22px 8px",
        background: colors.stone900,
        color: colors.stone50,
        fontFamily: FONT,
        fontSize: 18,
        fontWeight: 500,
        letterSpacing: "-0.02em",
        lineHeight: 1.3,
        opacity,
        transform: `translateY(${(1 - enter) * 18}px) scale(${0.94 + enter * 0.06})`,
        boxShadow: "0 18px 44px -18px rgba(28,25,23,0.6)",
      }}
    >
      {COMPOSE_PROMPT.split(COMPOSE_HIGHLIGHT).flatMap((part, i, arr) => {
        const nodes = [
          <span key={`t-${i}`} style={{ opacity: 0.85 }}>
            {part}
          </span>,
        ];
        if (i < arr.length - 1) {
          nodes.push(
            <span key={`h-${i}`} style={{ color: colors.amber }}>
              {COMPOSE_HIGHLIGHT}
            </span>,
          );
        }
        return nodes;
      })}
      <div
        style={{
          position: "absolute",
          bottom: -8,
          left: 36,
          width: 16,
          height: 16,
          background: colors.stone900,
          transform: "rotate(45deg)",
        }}
      />
    </div>
  );
};
