import React from "react";
import {
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { colors, FONT } from "../theme";
import { beats, commPings } from "../timing";
import { AgentOrb } from "./AgentOrb";

/** Slim orb rail above the thread — pings fire with replies / upvote. */
export const AgentsBridge: React.FC<{ orbSize?: number }> = ({
  orbSize = 48,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const enter = spring({
    frame: Math.max(0, frame - beats.critique.start),
    fps,
    config: { damping: 14, stiffness: 120 },
  });
  const exit = interpolate(
    frame,
    [beats.finalDoc.start - 20, beats.finalDoc.start + 28],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  if (frame < beats.critique.start - 2 || exit < 0.02) return null;

  const speakingClaude = commPings.some(
    (p) => frame >= p.start && frame < p.end && p.dir === 0,
  );
  const speakingGpt = commPings.some(
    (p) => frame >= p.start && frame < p.end && p.dir === 1,
  );

  const captionOpacity = interpolate(
    frame,
    [
      beats.critique.start + 8,
      beats.critique.start + 28,
      beats.critique.end - 60,
      beats.critique.end - 20,
    ],
    [0, 0.85, 0.85, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: 8,
        opacity: enter * exit,
        transform: `translateY(${(1 - enter) * 12}px)`,
        fontFamily: FONT,
        marginBottom: 10,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
        <AgentOrb
          brand="claude"
          label="@claude"
          accent={colors.alice}
          active={speakingClaude}
          intensity={speakingClaude ? 1 : 0.28}
          size={orbSize}
        />

        <div
          style={{
            position: "relative",
            width: 160,
            height: 48,
            marginTop: -18,
          }}
        >
          <div
            style={{
              position: "absolute",
              top: "50%",
              left: 4,
              right: 4,
              height: 2,
              borderRadius: 99,
              background: `linear-gradient(90deg, ${colors.alice}, ${colors.amber})`,
              opacity: 0.45,
              transform: "translateY(-50%)",
            }}
          />
          {commPings.map((p, i) => {
            const t = interpolate(frame, [p.start, p.end], [0, 1], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            });
            if (t <= 0 || t >= 1) return null;
            const x = p.dir === 0 ? t : 1 - t;
            const accent = p.dir === 0 ? colors.alice : colors.amber;
            const isUpvote = p.label.includes("upvote");
            return (
              <React.Fragment key={i}>
                <div
                  style={{
                    position: "absolute",
                    top: "50%",
                    left: `${x * 100}%`,
                    width: isUpvote ? 18 : 14,
                    height: isUpvote ? 18 : 14,
                    marginLeft: isUpvote ? -9 : -7,
                    marginTop: isUpvote ? -9 : -7,
                    borderRadius: "50%",
                    background: accent,
                    boxShadow: `0 0 ${isUpvote ? 22 : 16}px ${accent}`,
                    opacity: interpolate(t, [0, 0.12, 0.85, 1], [0, 1, 1, 0]),
                  }}
                />
                <div
                  style={{
                    position: "absolute",
                    top: isUpvote ? -2 : 0,
                    left: `${x * 100}%`,
                    transform: "translateX(-50%)",
                    padding: "3px 8px",
                    borderRadius: 999,
                    background: isUpvote ? colors.accent : colors.stone900,
                    color: colors.stone50,
                    fontSize: 10,
                    fontWeight: 600,
                    letterSpacing: "-0.01em",
                    whiteSpace: "nowrap",
                    opacity: interpolate(
                      t,
                      [0.1, 0.22, 0.78, 0.95],
                      [0, 1, 1, 0],
                    ),
                    boxShadow: "0 8px 18px -10px rgba(28,25,23,0.45)",
                  }}
                >
                  {p.label}
                </div>
              </React.Fragment>
            );
          })}
        </div>

        <AgentOrb
          brand="chatgpt"
          label="@chatgpt"
          accent={colors.amber}
          active={speakingGpt}
          intensity={speakingGpt ? 1 : 0.28}
          size={orbSize}
        />
      </div>

      <div
        style={{
          fontSize: 11,
          fontWeight: 500,
          color: colors.stone500,
          letterSpacing: "-0.01em",
          opacity: captionOpacity,
        }}
      >
        live on mutande
      </div>
    </div>
  );
};
