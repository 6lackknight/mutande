import React from "react";
import {
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { RECIPIENTS, SENDER_AGENTS, SENDER_HANDLE } from "../recipients";
import { colors, FONT } from "../theme";
import { beats } from "../timing";
import { AnimatedBeam } from "./AnimatedBeam";
import { BrandId, BrandMark } from "./BrandMark";

const AGENT_SIZE = 84;
const DEST_SIZE = 76;
const HUB_SIZE = 128;
const CARD_W = 268;

const NodeCircle: React.FC<{
  size: number;
  accent?: string;
  children: React.ReactNode;
  active?: boolean;
}> = ({ size, accent = colors.stone300, children, active = false }) => (
  <div
    style={{
      width: size,
      height: size,
      borderRadius: size * 0.28,
      background: "#fff",
      border: `2px solid ${active ? accent : colors.stone300}`,
      boxShadow: active
        ? `0 12px 28px -16px rgba(28,25,23,0.45), 0 0 0 3px ${accent}22`
        : "0 10px 24px -16px rgba(28,25,23,0.35)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      zIndex: 2,
    }}
  >
    {children}
  </div>
);

/** Agents (left) → mutande (hub) → recipients (right), Magic UI beams. */
export const EncryptedTransit: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const local = frame - beats.fanout.start;

  if (frame < beats.fanout.start - 4 || frame > beats.fanout.end + 4) {
    return null;
  }

  const stageFade = interpolate(
    frame,
    [beats.fanout.end - 36, beats.fanout.end],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  const graphIn = spring({
    frame: Math.max(0, local),
    fps,
    config: { damping: 16, stiffness: 95 },
    durationInFrames: 36,
  });

  // Content bounding box — sized so left icons + hub + right cards balance,
  // then centered in the 1080² frame.
  const contentW = AGENT_SIZE + 168 + HUB_SIZE + 168 + DEST_SIZE + 12 + CARD_W;
  // ≈ 884 — include hub caption + agent labels in vertical box
  const contentH = 620;
  const originX = (width - contentW) / 2;
  const originY = (height - contentH) / 2 + 28;

  const leftX = originX + AGENT_SIZE / 2;
  const midX = originX + AGENT_SIZE + 168 + HUB_SIZE / 2;
  const rightX = originX + AGENT_SIZE + 168 + HUB_SIZE + 168 + DEST_SIZE / 2;
  const colCount = Math.max(SENDER_AGENTS.length, RECIPIENTS.length, 1);
  const ys = Array.from({ length: colCount }, (_, i) =>
    originY +
    contentH *
      (colCount === 1 ? 0.5 : 0.22 + (0.56 * i) / Math.max(colCount - 1, 1)),
  );
  const hub = { x: midX, y: ys[Math.floor((ys.length - 1) / 2)] ?? ys[0]! };

  const agents = SENDER_AGENTS.map((a, i) => ({
    ...a,
    x: leftX,
    y: ys[i] ?? ys[0]!,
    curvature: i === 0 ? 40 : -40,
  }));

  const dests = RECIPIENTS.map((r, i) => ({
    ...r,
    x: rightX,
    y: ys[i] ?? ys[0]!,
    curvature: i === 0 ? -40 : 40,
  }));

  const beamLocal = Math.max(0, local - 24);
  const outDelay = 36;

  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        pointerEvents: "none",
        fontFamily: FONT,
        opacity: stageFade * graphIn,
      }}
    >
      <div
        style={{
          position: "absolute",
          left: midX,
          top: originY - 56,
          transform: "translateX(-50%)",
          fontSize: 15,
          fontWeight: 600,
          letterSpacing: "0.1em",
          textTransform: "uppercase",
          color: colors.stone500,
          opacity: interpolate(graphIn, [0.4, 1], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          }),
          whiteSpace: "nowrap",
        }}
      >
        sealed · routed by address
      </div>

      {agents.map((a, i) => (
        <AnimatedBeam
          key={`in-${a.id}`}
          id={`beam-in-${a.id}`}
          from={{ x: a.x, y: a.y }}
          to={hub}
          curvature={a.curvature}
          frame={beamLocal}
          delayInFrames={i * 10}
          durationInFrames={96}
          width={width}
          height={height}
          pathColor={colors.stone500}
          pathWidth={2.5}
          pathOpacity={0.28}
          gradientStartColor={a.accent}
          gradientStopColor={colors.accent}
          opacity={0.95}
        />
      ))}

      {dests.map((d, i) => (
        <AnimatedBeam
          key={`out-${d.id}`}
          id={`beam-out-${d.id}`}
          from={hub}
          to={{ x: d.x, y: d.y }}
          curvature={d.curvature}
          frame={beamLocal}
          delayInFrames={outDelay + i * 10}
          durationInFrames={96}
          width={width}
          height={height}
          pathColor={colors.stone500}
          pathWidth={2.5}
          pathOpacity={0.28}
          gradientStartColor={colors.amber}
          gradientStopColor={d.accent}
          opacity={0.95}
        />
      ))}

      {agents.map((a, i) => {
        const stagger = spring({
          frame: Math.max(0, local - i * 6),
          fps,
          config: { damping: 14, stiffness: 130 },
        });
        const active = beamLocal > i * 8 && beamLocal < i * 8 + 50;
        return (
          <div
            key={a.id}
            style={{
              position: "absolute",
              left: a.x - AGENT_SIZE / 2,
              top: a.y - AGENT_SIZE / 2,
              width: AGENT_SIZE,
              opacity: stagger,
              transform: `translateX(${(1 - stagger) * -24}px)`,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 10,
              zIndex: 2,
            }}
          >
            <NodeCircle size={AGENT_SIZE} accent={a.accent} active={active}>
              <BrandMark brand={a.brand as BrandId} size={38} />
            </NodeCircle>
            <span
              style={{
                fontSize: 16,
                fontWeight: 650,
                letterSpacing: "-0.02em",
                color: colors.stone900,
              }}
            >
              {a.handle}
            </span>
          </div>
        );
      })}

      <div
        style={{
          position: "absolute",
          left: hub.x - HUB_SIZE / 2,
          top: hub.y - HUB_SIZE / 2,
          width: HUB_SIZE,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 10,
          zIndex: 3,
          opacity: spring({
            frame: Math.max(0, local - 8),
            fps,
            config: { damping: 14, stiffness: 120 },
          }),
        }}
      >
        <div
          style={{
            width: HUB_SIZE,
            height: HUB_SIZE,
            borderRadius: 30,
            background: colors.stone900,
            border: `2px solid ${colors.accent}88`,
            boxShadow: "0 22px 48px -22px rgba(28,25,23,0.55)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            overflow: "hidden",
            flexShrink: 0,
          }}
        >
          <Img
            src={staticFile("brand/mt-mark.png")}
            style={{
              width: HUB_SIZE,
              height: HUB_SIZE,
              objectFit: "cover",
            }}
          />
        </div>
        <div
          style={{
            fontSize: 20,
            fontWeight: 650,
            letterSpacing: "-0.03em",
            color: colors.stone900,
          }}
        >
          mutande
        </div>
        <div
          style={{
            fontSize: 13,
            fontWeight: 600,
            color: colors.stone500,
            letterSpacing: "-0.01em",
          }}
        >
          {SENDER_HANDLE ? `@${SENDER_HANDLE}` : null}
        </div>
      </div>

      {dests.map((d, i) => {
        const stagger = spring({
          frame: Math.max(0, local - 12 - i * 6),
          fps,
          config: { damping: 14, stiffness: 120 },
        });
        const hit = spring({
          frame: Math.max(0, beamLocal - (outDelay + 40 + i * 8)),
          fps,
          config: { damping: 12, stiffness: 160 },
        });
        return (
          <div
            key={d.id}
            style={{
              position: "absolute",
              left: d.x - DEST_SIZE / 2,
              top: d.y - DEST_SIZE / 2,
              opacity: stagger,
              transform: `translateX(${(1 - stagger) * 24}px) scale(${1 + hit * 0.025})`,
              zIndex: 2,
              display: "flex",
              alignItems: "center",
              gap: 12,
            }}
          >
            <NodeCircle size={DEST_SIZE} accent={d.accent} active={hit > 0.4}>
              <BrandMark brand={d.brand} size={32} />
            </NodeCircle>
            <div
              style={{
                width: CARD_W,
                padding: "12px 14px",
                borderRadius: 12,
                background: "rgba(255,255,255,0.94)",
                border: `1.5px solid ${hit > 0.35 ? `${d.accent}77` : colors.stone300}`,
                boxShadow:
                  hit > 0.3
                    ? `0 14px 32px -20px rgba(28,25,23,0.4), 0 0 0 3px ${d.accent}14`
                    : "0 12px 28px -20px rgba(28,25,23,0.3)",
              }}
            >
              <div
                style={{
                  fontSize: d.handle.length > 16 ? 13 : 15,
                  fontWeight: 650,
                  letterSpacing: "-0.025em",
                  color: colors.stone900,
                  lineHeight: 1.2,
                  wordBreak: "break-all" as const,
                }}
              >
                {d.handle}
              </div>
              <div
                style={{
                  marginTop: 4,
                  fontSize: 10,
                  fontWeight: 700,
                  letterSpacing: "0.08em",
                  textTransform: "uppercase",
                  color: hit > 0.4 ? colors.accent : colors.stone500,
                  opacity: 0.5 + hit * 0.5,
                }}
              >
                sealed
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
};
