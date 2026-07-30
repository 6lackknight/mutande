import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { colors, FONT } from "../theme";

type Side = "left" | "right";

type Props = {
  text: string;
  side: Side;
  accent: string;
  appearAt: number;
  disappearAt?: number;
  maxWidth?: number;
  /** YC-style hero bubble */
  cinematic?: boolean;
};

export const ChatBubble: React.FC<Props> = ({
  text,
  side,
  accent,
  appearAt,
  disappearAt,
  maxWidth = 280,
  cinematic = false,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - appearAt;
  const enter = spring({
    frame: Math.max(0, local),
    fps,
    config: { damping: cinematic ? 16 : 14, stiffness: cinematic ? 100 : 140 },
  });
  const exit =
    disappearAt === undefined
      ? 1
      : interpolate(frame, [disappearAt - 18, disappearAt], [1, 0], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        });
  if (frame < appearAt - 1) return null;
  const opacity = enter * exit;
  if (opacity < 0.01) return null;

  const fromLeft = side === "left";
  const pad = cinematic ? "28px 32px" : "14px 18px";
  const fontSize = cinematic ? 28 : 16;
  const radius = cinematic
    ? fromLeft
      ? "28px 28px 28px 8px"
      : "28px 28px 8px 28px"
    : fromLeft
      ? "18px 18px 18px 6px"
      : "18px 18px 6px 18px";

  return (
    <div
      style={{
        alignSelf: fromLeft ? "flex-start" : "flex-end",
        maxWidth: cinematic ? Math.max(maxWidth, 520) : maxWidth,
        width: cinematic ? "100%" : undefined,
        opacity,
        transform: `translateY(${(1 - enter) * (cinematic ? 28 : 14)}px) scale(${0.88 + enter * 0.12})`,
        fontFamily: FONT,
      }}
    >
      <div
        style={{
          position: "relative",
          padding: pad,
          borderRadius: radius,
          background: fromLeft ? "#fff" : colors.stone900,
          color: fromLeft ? colors.stone900 : colors.stone50,
          border: fromLeft ? `2px solid ${accent}66` : "none",
          boxShadow: cinematic
            ? fromLeft
              ? `0 24px 60px -20px rgba(28,25,23,0.4), 0 0 0 1px ${accent}33`
              : "0 28px 70px -18px rgba(28,25,23,0.65)"
            : fromLeft
              ? `0 10px 28px -14px rgba(28,25,23,0.35), 0 0 0 1px ${accent}22`
              : "0 12px 32px -16px rgba(28,25,23,0.55)",
          fontSize,
          fontWeight: cinematic ? 600 : 500,
          lineHeight: 1.3,
          letterSpacing: "-0.025em",
        }}
      >
        {text}
        <div
          style={{
            position: "absolute",
            bottom: cinematic ? -10 : -7,
            [fromLeft ? "left" : "right"]: cinematic ? 22 : 14,
            width: cinematic ? 18 : 14,
            height: cinematic ? 18 : 14,
            background: fromLeft ? "#fff" : colors.stone900,
            borderRight: fromLeft ? `2px solid ${accent}66` : undefined,
            borderBottom: fromLeft ? `2px solid ${accent}66` : undefined,
            transform: "rotate(45deg)",
          }}
        />
      </div>
    </div>
  );
};
