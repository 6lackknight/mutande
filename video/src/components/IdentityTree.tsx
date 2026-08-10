import React from "react";
import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { PARTICIPANTS } from "../participants";
import { colors, FONT } from "../theme";
import { COMPOSE_PROMPT, DRAFT_FILENAME, beats } from "../timing";

const BACKDROP_ROWS = [
  "Q3 plan critique",
  "Ping @all",
  "Blob handoff",
  "Safety numbers",
] as const;

/**
 * Opening beat — Variant C: participants popover over a blurred inbox.
 * Same cast as compose / collab / fan-out.
 */
export const IdentityTree: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { start, end } = beats.identity;

  if (frame < start || frame > end + 4) return null;

  const sheetIn = spring({
    frame: Math.max(0, frame - start - 8),
    fps,
    config: { damping: 16, stiffness: 100 },
    durationInFrames: 32,
  });
  const fadeOut = interpolate(frame, [end - 36, end], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const fadeIn = interpolate(frame, [start, start + 10], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const backdropIn = interpolate(frame, [start, start + 18], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        fontFamily: FONT,
        opacity: fadeIn * fadeOut,
        backgroundColor: colors.stone200,
      }}
    >
      {/* Blurred inbox backdrop */}
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

      {/* Participants sheet */}
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
            width: 400,
            borderRadius: 20,
            border: `1px solid ${colors.stone200}`,
            background: "rgba(250,249,247,0.96)",
            padding: 18,
            boxShadow:
              "0 36px 72px -28px rgba(28,25,23,0.45), 0 0 0 1px rgba(28,25,23,0.04)",
            opacity: sheetIn,
            transform: `translateY(${(1 - sheetIn) * 28}px) scale(${0.94 + sheetIn * 0.06})`,
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              padding: "0 4px 12px",
            }}
          >
            <div
              style={{
                fontSize: 15,
                fontWeight: 650,
                color: colors.stone800,
                letterSpacing: "-0.02em",
              }}
            >
              On this thread
            </div>
            <div
              style={{
                borderRadius: 999,
                background: colors.amberSoft,
                color: colors.amber,
                fontSize: 12,
                fontWeight: 650,
                padding: "3px 9px",
              }}
            >
              {PARTICIPANTS.length}
            </div>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {PARTICIPANTS.map((p, i) => {
              const row = spring({
                frame: Math.max(0, frame - start - 22 - i * 10),
                fps,
                config: { damping: 16, stiffness: 130 },
              });
              return (
                <div
                  key={p.id}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 12,
                    borderRadius: 14,
                    background: "#fff",
                    padding: "12px 14px",
                    boxShadow: `inset 0 0 0 1px ${colors.stone200}`,
                    opacity: row,
                    transform: `translateY(${(1 - row) * 10}px)`,
                  }}
                >
                  <div
                    style={{
                      width: 8,
                      height: 8,
                      borderRadius: 99,
                      background: colors.stone800,
                      flexShrink: 0,
                    }}
                  />
                  <div
                    style={{
                      flex: 1,
                      minWidth: 0,
                      fontFamily:
                        "ui-monospace, SFMono-Regular, Menlo, monospace",
                      fontSize: 14,
                      fontWeight: 600,
                      color: colors.stone900,
                      letterSpacing: "-0.02em",
                      overflow: "hidden",
                      textOverflow: "ellipsis",
                      whiteSpace: "nowrap",
                    }}
                  >
                    {p.address}
                  </div>
                  <div
                    style={{
                      flexShrink: 0,
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
                    {p.hostHint}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};
