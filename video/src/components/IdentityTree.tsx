import React from "react";
import {
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { colors, FONT } from "../theme";
import { IDENTITY_AGENTS, IDENTITY_HANDLE, beats } from "../timing";

/** Opening beat — one handle, nested agent addresses. Large. Quiet. */
export const IdentityTree: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { start, end } = beats.identity;

  if (frame < start || frame > end + 4) return null;

  const enter = spring({
    frame: Math.max(0, frame - start),
    fps,
    config: { damping: 18, stiffness: 90 },
    durationInFrames: 36,
  });
  const fadeOut = interpolate(frame, [end - 36, end], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const fadeIn = interpolate(frame, [start, start + 12], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const breathe = 1 + Math.sin((frame - start) * 0.025) * 0.006;

  return (
    <div
      style={{
        opacity: fadeIn * fadeOut * Math.min(1, enter + 0.1),
        transform: `translateY(${(1 - enter) * 24}px) scale(${(0.96 + enter * 0.04) * breathe})`,
        fontFamily: FONT,
        display: "flex",
        flexDirection: "column",
        alignItems: "flex-start",
        gap: 28,
        maxWidth: 820,
      }}
    >
      <div
        style={{
          fontSize: 64,
          fontWeight: 700,
          letterSpacing: "-0.045em",
          color: colors.stone900,
          lineHeight: 1.05,
        }}
      >
        {IDENTITY_HANDLE}
      </div>

      <div
        style={{
          display: "flex",
          flexDirection: "column",
          gap: 14,
          paddingLeft: 8,
          borderLeft: `2px solid ${colors.stone300}`,
          marginLeft: 6,
        }}
      >
        {IDENTITY_AGENTS.map((agent, i) => {
          const stagger = spring({
            frame: Math.max(0, frame - start - 28 - i * 14),
            fps,
            config: { damping: 16, stiffness: 110 },
          });
          return (
            <div
              key={agent}
              style={{
                opacity: stagger,
                transform: `translateX(${(1 - stagger) * 28}px)`,
                display: "flex",
                alignItems: "baseline",
                gap: 14,
                paddingLeft: 22,
              }}
            >
              <span
                style={{
                  fontSize: 22,
                  fontWeight: 500,
                  color: colors.stone500,
                  fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
                }}
              >
                {i === IDENTITY_AGENTS.length - 1 ? "└" : "├"}
              </span>
              <span
                style={{
                  fontSize: 40,
                  fontWeight: 600,
                  letterSpacing: "-0.035em",
                  color: colors.accent,
                }}
              >
                {agent}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
};
