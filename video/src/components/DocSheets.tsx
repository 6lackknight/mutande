import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { colors, FONT } from "../theme";
import { beats, critiquePasses, DRAFT_FILENAME } from "../timing";

type Props = {
  finalize: number;
  lift?: number;
  /** Larger for fullscreen Alice; smaller in dual-plate */
  scale?: number;
  /** Show active critique diff motion */
  critique?: boolean;
};

const Line: React.FC<{
  width: string;
  opacity?: number;
  highlight?: number;
}> = ({ width, opacity = 1, highlight = 0 }) => (
  <div
    style={{
      height: 8,
      width,
      borderRadius: 4,
      background: highlight > 0.3 ? colors.amber : colors.stone300,
      opacity,
      marginBottom: 10,
      transform: `scaleX(${1 + highlight * 0.04})`,
      transformOrigin: "left center",
    }}
  />
);

export const DocSheets: React.FC<Props> = ({
  finalize,
  lift = 0,
  scale = 1,
  critique = false,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const activePass = critiquePasses.findIndex(
    (p) => frame >= p.start && frame < p.end,
  );
  const passLocal =
    activePass >= 0
      ? interpolate(
          frame,
          [critiquePasses[activePass].start, critiquePasses[activePass].end],
          [0, 1],
          { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
        )
      : 0;

  // Alternate which sheet leads each pass
  const slide =
    critique && activePass >= 0
      ? Math.sin(passLocal * Math.PI) *
        (activePass === 1 ? -18 : 18) *
        (1 - finalize)
      : 0;

  const stackPop = spring({
    frame: Math.max(0, frame - beats.critique.start),
    fps,
    config: { damping: 14, stiffness: 140 },
  });

  const stackOffset = interpolate(finalize, [0, 1], [16, 0]);
  const topFade = interpolate(finalize, [0, 1], [1, 0]);
  const clean = interpolate(finalize, [0.2, 1], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const highlightA =
    critique && activePass === 0
      ? Math.sin(passLocal * Math.PI)
      : critique && activePass === 2
        ? Math.sin(passLocal * Math.PI) * 0.6
        : 0;
  const highlightB =
    critique && activePass === 1 ? Math.sin(passLocal * Math.PI) : 0;

  const w = 220 * scale;
  const h = 260 * scale;

  return (
    <div
      style={{
        position: "relative",
        width: w,
        height: h,
        margin: "0 auto",
        opacity: (0.3 + stackPop * 0.7) * (1 - lift),
        transform: `translateY(${-lift * 80}px) scale(${(0.92 + stackPop * 0.08) * (1 - lift * 0.55)}) rotate(${(1 - finalize) * slide * 0.05}deg)`,
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: 14,
          background: colors.stone100,
          border: `1px solid ${colors.stone300}`,
          transform: `translate(${stackOffset + slide * 0.3}px, ${stackOffset}px)`,
          opacity: topFade * 0.9,
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: 14,
          background: colors.accentSoft,
          border: `1.5px solid ${colors.accent}66`,
          transform: `translate(${stackOffset * 0.5 - slide}px, ${stackOffset * 0.5}px) rotate(${(1 - finalize) * -3}deg)`,
          opacity: topFade * (0.55 + highlightB * 0.45),
          boxShadow:
            highlightB > 0.2 ? `0 0 24px ${colors.amber}55` : undefined,
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: 14,
          background: "#fff",
          border: `1px solid ${colors.stone300}`,
          padding: 24 * scale,
          boxShadow: "0 14px 32px -16px rgba(28,25,23,0.45)",
          transform: `translateX(${slide * 0.35}px)`,
        }}
      >
        <div
          style={{
            fontFamily: FONT,
            fontSize: Math.max(10, 13 * scale),
            fontWeight: 600,
            letterSpacing: "-0.02em",
            color: colors.stone900,
            opacity: 0.75 + clean * 0.25,
            marginBottom: 14 * scale,
            whiteSpace: "nowrap",
            overflow: "hidden",
            textOverflow: "ellipsis",
          }}
        >
          {DRAFT_FILENAME}
        </div>
        <Line
          width="94%"
          opacity={0.5 + clean * 0.4}
          highlight={highlightA}
        />
        <Line
          width="72%"
          opacity={0.45 + clean * 0.4}
          highlight={highlightB}
        />
        <Line
          width="90%"
          opacity={0.4 + clean * 0.45}
          highlight={highlightA * 0.7}
        />
        <Line
          width={`${55 + clean * 35}%`}
          opacity={0.35 + clean * 0.55}
          highlight={highlightB * 0.8}
        />
        <div
          style={{
            marginTop: 18 * scale,
            height: 52 * scale,
            borderRadius: 10,
            background: `linear-gradient(135deg, ${colors.accentSoft}, ${colors.stone100})`,
            border: `1px solid ${colors.accent}44`,
            opacity: 0.3 + clean * 0.7,
            transform: `scale(${0.96 + clean * 0.04})`,
          }}
        />
      </div>
    </div>
  );
};
