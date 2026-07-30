import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { RECIPIENTS } from "../recipients";
import { colors, FONT } from "../theme";
import { beats } from "../timing";

const SHARDS_PER_ARC = 5;

/** Arc from Alice seal toward a destination (y varies per recipient). */
const arcTo = (u: number, destY: number) => {
  const x0 = 0.3;
  const y0 = 0.5;
  const x1 = 0.7;
  const y1 = destY;
  const cx = 0.5;
  const cy = Math.min(y0, destY) - 0.14;
  const o = 1 - u;
  return {
    x: o * o * x0 + 2 * o * u * cx + u * u * x1,
    y: o * o * y0 + 2 * o * u * cy + u * u * y1,
  };
};

const DEST_Y = [0.28, 0.5, 0.72] as const;

export const EncryptedTransit: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const { start, end } = beats.transit;
  const t = interpolate(frame, [start, end], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const sealForm = interpolate(t, [0, 0.12], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const shardPhase = interpolate(t, [0.1, 0.58], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const assemble = interpolate(t, [0.52, 0.78], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const assemblePop = spring({
    frame: Math.max(0, frame - (start + Math.floor((end - start) * 0.55))),
    fps,
    config: { damping: 12, stiffness: 160 },
  });
  const labelOpacity = interpolate(t, [0.12, 0.22, 0.5, 0.62], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const capsuleGone = interpolate(t, [0.72, 0.88], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const laneOpacity = interpolate(t, [0.08, 0.18, 0.7, 0.85], [0, 0.9, 0.9, 0]);
  const fanSplit = interpolate(t, [0.14, 0.28], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const origin = { x: 0.3, y: 0.5 };

  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        pointerEvents: "none",
        fontFamily: FONT,
      }}
    >
      <svg
        width={width}
        height={height}
        style={{ position: "absolute", inset: 0, opacity: laneOpacity }}
      >
        {DEST_Y.map((dy, i) => {
          const p0 = arcTo(0, dy);
          const p1 = arcTo(1, dy);
          const cy = Math.min(0.5, dy) - 0.14;
          const d = `M ${p0.x * width} ${p0.y * height} Q ${0.5 * width} ${cy * height} ${p1.x * width} ${p1.y * height}`;
          return (
            <path
              key={i}
              d={d}
              fill="none"
              stroke={RECIPIENTS[i].accent}
              strokeWidth={2.2}
              strokeLinecap="round"
              strokeDasharray="6 10"
              opacity={0.35 + fanSplit * 0.35}
            />
          );
        })}
      </svg>

      {/* One seal, then fan-out */}
      <div
        style={{
          position: "absolute",
          left: origin.x * width - 22,
          top: origin.y * height - 28,
          width: 44,
          height: 56,
          borderRadius: 12,
          background: colors.stone900,
          opacity: sealForm * (1 - shardPhase * 0.9) * capsuleGone,
          transform: `scale(${0.5 + sealForm * 0.5})`,
          boxShadow: `0 0 28px ${colors.accent}99`,
        }}
      />

      {DEST_Y.flatMap((dy, destIndex) =>
        Array.from({ length: SHARDS_PER_ARC }).map((_, i) => {
          const stagger = i / (SHARDS_PER_ARC - 1);
          const u = interpolate(
            shardPhase,
            [stagger * 0.1 + destIndex * 0.02, 0.4 + stagger * 0.5],
            [stagger * 0.1, 0.9],
            { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
          );
          const pt = arcTo(u, dy);
          const endPt = arcTo(0.92, dy);
          const x = pt.x * (1 - assemble) + endPt.x * assemble;
          const y = pt.y * (1 - assemble) + endPt.y * assemble;
          const opacity =
            interpolate(
              shardPhase,
              [stagger * 0.1, stagger * 0.1 + 0.1],
              [0, 1],
              { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
            ) *
            fanSplit *
            (1 - assemble * 0.95);
          const ahead = arcTo(Math.min(1, u + 0.04), dy);
          const angle =
            (Math.atan2(ahead.y - pt.y, ahead.x - pt.x) * 180) / Math.PI;

          return (
            <div
              key={`${destIndex}-${i}`}
              style={{
                position: "absolute",
                left: x * width - 6,
                top: y * height - 8,
                width: 12,
                height: 16,
                borderRadius: 4,
                background:
                  i % 2 === 0 ? colors.stone900 : RECIPIENTS[destIndex].accent,
                opacity,
                transform: `rotate(${angle}deg) scale(${1 - assemble * 0.35})`,
              }}
            />
          );
        }),
      )}

      {DEST_Y.map((dy, i) => {
        const dest = arcTo(0.92, dy);
        return (
          <div
            key={`cap-${i}`}
            style={{
              position: "absolute",
              left: dest.x * width - 16,
              top: dest.y * height - 20,
              width: 32,
              height: 40,
              borderRadius: 10,
              background: colors.stone900,
              opacity: assemble * capsuleGone,
              transform: `scale(${0.4 + assemblePop * 0.65})`,
              boxShadow: `0 0 ${12 + assemblePop * 28}px ${RECIPIENTS[i].accent}`,
            }}
          />
        );
      })}

      <div
        style={{
          position: "absolute",
          left: "50%",
          top: "12%",
          transform: "translateX(-50%)",
          fontSize: 13,
          fontWeight: 700,
          letterSpacing: "0.16em",
          textTransform: "uppercase",
          color: colors.encrypted,
          opacity: labelOpacity,
          textShadow: "0 1px 0 rgba(255,255,255,0.6)",
        }}
      >
        encrypted · fan-out
      </div>
    </div>
  );
};
