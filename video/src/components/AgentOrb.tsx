import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { colors, FONT } from "../theme";
import { BrandId, BrandMark } from "./BrandMark";

type Props = {
  label: string;
  brand: BrandId;
  accent: string;
  active?: boolean;
  size?: number;
  intensity?: number;
};

export const AgentOrb: React.FC<Props> = ({
  label,
  brand,
  accent,
  active = false,
  size = 56,
  intensity = 0,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pulse = active
    ? spring({
        frame: frame % 28,
        fps,
        config: { damping: 12, stiffness: 160 },
      })
    : 0;
  const speak = active ? Math.max(intensity, pulse * 0.5) : 0;
  const scale = 1 + speak * 0.12;
  const glow = 0.08 + speak * 0.45;
  const glowHex = Math.round(interpolate(glow, [0, 1], [0, 255]))
    .toString(16)
    .padStart(2, "0");
  const markSize = size * 0.52;

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: 10,
        fontFamily: FONT,
        opacity: active ? 1 : 0.5,
        transform: `scale(${active ? 1 : 0.94})`,
      }}
    >
      <div
        style={{
          width: size,
          height: size,
          borderRadius: size * 0.28,
          background: colors.stone200,
          border: `1.5px solid ${active ? accent : colors.stone300}`,
          boxShadow: active
            ? `0 0 ${18 + glow * 36}px ${accent}${glowHex}, 0 8px 20px -12px rgba(28,25,23,0.35)`
            : "0 6px 16px -12px rgba(28,25,23,0.25)",
          transform: `scale(${scale})`,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <BrandMark brand={brand} size={markSize} />
      </div>
      <span
        style={{
          fontSize: Math.max(13, size * 0.24),
          fontWeight: active ? 600 : 500,
          letterSpacing: "-0.01em",
          color: active ? colors.stone900 : colors.stone500,
        }}
      >
        {label}
      </span>
    </div>
  );
};
