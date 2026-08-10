import React from "react";
import {
  AbsoluteFill,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { colors, FONT } from "../theme";
import {
  COMPOSE_HIGHLIGHT,
  COMPOSE_PROMPT,
  DRAFT_FILENAME,
  beats,
} from "../timing";

const BACKDROP_ROWS = [
  "Q3 plan critique",
  "Ping @all",
  "Blob handoff",
  "Safety numbers",
] as const;

/** Compose beat — same sheet-over-blur UI language as Variant C opening. */
export const ComposeWindow: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - beats.compose.start;

  if (frame < beats.compose.start - 2 || frame > beats.compose.end + 4) {
    return null;
  }

  const enter = spring({
    frame: Math.max(0, local),
    fps,
    config: { damping: 16, stiffness: 90 },
    durationInFrames: 28,
  });

  const typeStart = 28;
  const typeEnd = 200;
  const typedCount = Math.floor(
    interpolate(local, [typeStart, typeEnd], [0, COMPOSE_PROMPT.length], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    }),
  );
  const typed = COMPOSE_PROMPT.slice(0, typedCount);
  const caretOn =
    local < typeEnd + 20
      ? Math.floor(local / 16) % 2 === 0
      : local < beats.compose.end - beats.compose.start - 20;

  const doneTyping = typedCount >= COMPOSE_PROMPT.length;
  const sendPulse = spring({
    frame: Math.max(0, local - typeEnd - 8),
    fps,
    config: { damping: 12, stiffness: 160 },
  });

  const exit = interpolate(
    frame,
    [beats.compose.end - 36, beats.compose.end],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  const resolveOpacity = interpolate(
    local,
    [typeEnd + 4, typeEnd + 24, typeEnd + 70, typeEnd + 95],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  const backdropIn = interpolate(local, [0, 14], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const renderTyped = () => {
    const hi = COMPOSE_HIGHLIGHT;
    const idx = typed.indexOf(hi);
    if (idx < 0) return typed;
    return (
      <>
        {typed.slice(0, idx)}
        <span style={{ color: colors.accent, fontWeight: 650 }}>
          {typed.slice(idx, idx + hi.length)}
        </span>
        {typed.slice(idx + hi.length)}
      </>
    );
  };

  return (
    <AbsoluteFill
      style={{
        fontFamily: FONT,
        opacity: enter * exit,
        backgroundColor: colors.stone200,
      }}
    >
      {/* Same blurred inbox as opening C */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          display: "flex",
          alignItems: "flex-start",
          justifyContent: "center",
          padding: "72px 48px",
          transform: "scale(1.06)",
          filter: "blur(3.5px) saturate(0.75)",
          opacity: 0.72 * backdropIn,
          pointerEvents: "none",
        }}
      >
        <div
          style={{
            width: "100%",
            maxWidth: 520,
            display: "flex",
            flexDirection: "column",
            gap: 14,
          }}
        >
          {BACKDROP_ROWS.map((title) => (
            <div
              key={title}
              style={{
                borderRadius: 14,
                border: `1px solid ${colors.stone300}`,
                background: colors.stone50,
                padding: "14px 16px",
              }}
            >
              <div
                style={{
                  fontSize: 16,
                  fontWeight: 600,
                  color: colors.stone700,
                  letterSpacing: "-0.02em",
                }}
              >
                {title}
              </div>
              <div
                style={{
                  marginTop: 6,
                  fontSize: 13,
                  color: colors.stone400,
                  overflow: "hidden",
                  whiteSpace: "nowrap",
                  textOverflow: "ellipsis",
                }}
              >
                {title === BACKDROP_ROWS[0]
                  ? COMPOSE_PROMPT
                  : `${DRAFT_FILENAME} · nested replies`}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Sheet — matches IdentityTree / Variant C */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          padding: 40,
        }}
      >
        <div
          style={{
            width: 440,
            borderRadius: 20,
            border: `1px solid ${colors.stone200}`,
            background: "rgba(250,249,247,0.96)",
            padding: 18,
            boxShadow:
              "0 36px 72px -28px rgba(28,25,23,0.45), 0 0 0 1px rgba(28,25,23,0.04)",
            transform: `translateY(${(1 - enter) * 28}px) scale(${0.94 + enter * 0.06})`,
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              padding: "0 4px 14px",
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 8,
              }}
            >
              <Img
                src={staticFile("hosts/claude.png")}
                style={{
                  width: 16,
                  height: 16,
                  objectFit: "contain",
                  filter: "brightness(0) saturate(100%)",
                  opacity: 0.85,
                }}
              />
              <div
                style={{
                  fontSize: 15,
                  fontWeight: 650,
                  color: colors.stone800,
                  letterSpacing: "-0.02em",
                }}
              >
                Claude
              </div>
            </div>
            <div
              style={{
                borderRadius: 8,
                background: colors.stone100,
                color: colors.stone500,
                fontSize: 10,
                fontWeight: 700,
                letterSpacing: "0.06em",
                textTransform: "uppercase",
                padding: "4px 7px",
              }}
            >
              Host
            </div>
          </div>

          {/* Message card — same row language as participants */}
          <div
            style={{
              borderRadius: 14,
              background: "#fff",
              padding: "14px 14px 12px",
              boxShadow: `inset 0 0 0 1px ${colors.stone200}`,
              marginBottom: 10,
            }}
          >
            <div
              style={{
                fontSize: 12,
                fontWeight: 650,
                color: colors.stone500,
                marginBottom: 6,
                letterSpacing: "-0.01em",
              }}
            >
              Claude
            </div>
            <div
              style={{
                fontSize: 15,
                color: colors.stone700,
                lineHeight: 1.4,
                letterSpacing: "-0.015em",
              }}
            >
              Draft ready. Want another intelligence to review before we send?
            </div>
            <div
              style={{
                marginTop: 12,
                display: "inline-flex",
                alignItems: "center",
                gap: 8,
                borderRadius: 10,
                background: colors.stone100,
                padding: "7px 10px",
                fontSize: 12,
                fontWeight: 600,
                color: colors.stone800,
                letterSpacing: "-0.02em",
              }}
            >
              <span
                style={{
                  width: 8,
                  height: 10,
                  borderRadius: 2,
                  border: `1.5px solid ${colors.stone500}`,
                  opacity: 0.7,
                }}
              />
              {DRAFT_FILENAME}
            </div>
          </div>

          {resolveOpacity > 0.02 ? (
            <div
              style={{
                marginBottom: 10,
                opacity: resolveOpacity,
                display: "flex",
                alignItems: "center",
                gap: 10,
                borderRadius: 14,
                background: "#fff",
                padding: "11px 14px",
                boxShadow: `inset 0 0 0 1.5px ${colors.accent}55`,
              }}
            >
              <div
                style={{
                  width: 8,
                  height: 8,
                  borderRadius: 99,
                  background: colors.accent,
                  flexShrink: 0,
                }}
              />
              <div
                style={{
                  flex: 1,
                  fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
                  fontSize: 13,
                  fontWeight: 600,
                  color: colors.stone900,
                  letterSpacing: "-0.02em",
                }}
              >
                {COMPOSE_HIGHLIGHT}
              </div>
              <div
                style={{
                  borderRadius: 8,
                  background: colors.amberSoft,
                  color: colors.amber,
                  fontSize: 10,
                  fontWeight: 700,
                  letterSpacing: "0.06em",
                  textTransform: "uppercase",
                  padding: "4px 7px",
                }}
              >
                OpenClaw
              </div>
            </div>
          ) : null}

          {/* Composer — white inset like C rows */}
          <div
            style={{
              borderRadius: 14,
              background: "#fff",
              padding: "12px 12px 10px",
              boxShadow: doneTyping
                ? `inset 0 0 0 1.5px ${colors.accent}66, 0 0 0 3px ${colors.accent}18`
                : `inset 0 0 0 1px ${colors.stone200}`,
            }}
          >
            <div
              style={{
                minHeight: 52,
                fontSize: 14,
                fontWeight: 500,
                color: colors.stone900,
                letterSpacing: "-0.02em",
                lineHeight: 1.4,
                marginBottom: 10,
              }}
            >
              {typed.length === 0 ? (
                <span style={{ color: colors.stone400, fontWeight: 400 }}>
                  Ask an address…
                  {caretOn ? (
                    <span
                      style={{
                        display: "inline-block",
                        width: 2,
                        height: "1.05em",
                        marginLeft: 2,
                        background: colors.stone700,
                        verticalAlign: "text-bottom",
                      }}
                    />
                  ) : null}
                </span>
              ) : (
                <span style={{ whiteSpace: "pre-wrap" }}>
                  {renderTyped()}
                  {caretOn ? (
                    <span
                      style={{
                        display: "inline-block",
                        width: 2,
                        height: "1.05em",
                        marginLeft: 1,
                        background: colors.stone900,
                        verticalAlign: "text-bottom",
                      }}
                    />
                  ) : null}
                </span>
              )}
            </div>
            <div
              style={{
                display: "flex",
                justifyContent: "flex-end",
                alignItems: "center",
              }}
            >
              <div
                style={{
                  width: 34,
                  height: 34,
                  borderRadius: 99,
                  background: doneTyping ? colors.stone800 : colors.stone300,
                  color: "#fff",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontSize: 15,
                  fontWeight: 700,
                  transform: `scale(${0.92 + sendPulse * 0.12})`,
                }}
              >
                ↑
              </div>
            </div>
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};
