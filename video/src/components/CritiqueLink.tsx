import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { colors } from "../theme";
import { critiquePasses } from "../timing";

/** Visible ping traveling Claude ↔ ChatGPT each critique pass. */
export const CritiqueLink: React.FC<{ width?: number }> = ({ width = 120 }) => {
  const frame = useCurrentFrame();

  return (
    <div
      style={{
        position: "relative",
        width,
        height: 28,
        marginTop: -8,
      }}
    >
      <div
        style={{
          position: "absolute",
          top: "50%",
          left: 8,
          right: 8,
          height: 2,
          background: `linear-gradient(90deg, ${colors.alice}55, ${colors.amber}55)`,
          opacity: 0.55,
          transform: "translateY(-50%)",
        }}
      />
      {critiquePasses.map((pass, i) => {
        const t = interpolate(frame, [pass.start, pass.end], [0, 1], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        });
        if (t <= 0 || t >= 1) return null;
        // Pass 0 & 2: left→right; pass 1: right→left
        const goRight = i !== 1;
        const x = goRight ? t : 1 - t;
        const accent = goRight ? colors.alice : colors.amber;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              top: "50%",
              left: `${x * 100}%`,
              width: 14,
              height: 14,
              marginLeft: -7,
              marginTop: -7,
              borderRadius: "50%",
              background: accent,
              boxShadow: `0 0 16px ${accent}`,
              opacity: interpolate(t, [0, 0.15, 0.85, 1], [0, 1, 1, 0]),
            }}
          />
        );
      })}
    </div>
  );
};
