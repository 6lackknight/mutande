import React from "react";
import {
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { colors, FONT } from "../theme";
import { COMPOSE_PROMPT, DRAFT_FILENAME, beats } from "../timing";

/** Claude Desktop window — user is already in Claude, typing a mutande ask. */
export const ComposeWindow: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const enter = spring({
    frame,
    fps,
    config: { damping: 16, stiffness: 90 },
    durationInFrames: 28,
  });

  const typeStart = 36;
  const typeEnd = 200;
  const typedCount = Math.floor(
    interpolate(frame, [typeStart, typeEnd], [0, COMPOSE_PROMPT.length], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    }),
  );
  const typed = COMPOSE_PROMPT.slice(0, typedCount);
  const caretOn =
    frame < typeEnd + 20
      ? Math.floor(frame / 16) % 2 === 0
      : frame < beats.compose.end - 20;

  const doneTyping = typedCount >= COMPOSE_PROMPT.length;
  const sendPulse = spring({
    frame: Math.max(0, frame - typeEnd - 8),
    fps,
    config: { damping: 12, stiffness: 160 },
  });

  const exit = interpolate(
    frame,
    [beats.compose.end - 36, beats.compose.end],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  const renderTyped = () => {
    const parts: React.ReactNode[] = [];
    const re = /(@chatgpt)|(\s+)|([^\s@]+)/g;
    let m: RegExpExecArray | null;
    let key = 0;
    while ((m = re.exec(typed)) !== null) {
      if (m[1]) {
        parts.push(
          <span key={key++} style={{ color: colors.amber, fontWeight: 600 }}>
            {m[1]}
          </span>,
        );
      } else {
        parts.push(<span key={key++}>{m[0]}</span>);
      }
    }
    return parts;
  };

  return (
    <div
      style={{
        opacity: enter * exit,
        transform: `translateY(${(1 - enter) * 36}px) scale(${0.94 + enter * 0.06})`,
        width: 760,
        fontFamily: FONT,
        borderRadius: 16,
        overflow: "hidden",
        background: "#f5f0e8",
        border: `1px solid ${colors.stone300}`,
        boxShadow:
          "0 40px 80px -28px rgba(28,25,23,0.45), 0 0 0 1px rgba(28,25,23,0.04)",
      }}
    >
      {/* Claude title bar */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 10,
          padding: "12px 14px",
          background: "#efe8dc",
          borderBottom: `1px solid ${colors.stone300}`,
        }}
      >
        <div style={{ display: "flex", gap: 7 }}>
          <div style={{ width: 11, height: 11, borderRadius: 99, background: "#ff5f57" }} />
          <div style={{ width: 11, height: 11, borderRadius: 99, background: "#febc2e" }} />
          <div style={{ width: 11, height: 11, borderRadius: 99, background: "#28c840" }} />
        </div>
        <div
          style={{
            flex: 1,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
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
          <span
            style={{
              fontSize: 13,
              fontWeight: 600,
              color: colors.stone700,
              letterSpacing: "-0.01em",
            }}
          >
            Claude
          </span>
        </div>
        <div style={{ width: 52 }} />
      </div>

      {/* Chat body */}
      <div
        style={{
          padding: "22px 24px 12px",
          minHeight: 200,
          background: "#f5f0e8",
        }}
      >
        {/* Prior Claude turn */}
        <div
          style={{
            display: "flex",
            gap: 12,
            marginBottom: 18,
            alignItems: "flex-start",
          }}
        >
          <div
            style={{
              width: 28,
              height: 28,
              borderRadius: 8,
              background: colors.stone200,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              flexShrink: 0,
            }}
          >
            <Img
              src={staticFile("hosts/claude.png")}
              style={{
                width: 16,
                height: 16,
                filter: "brightness(0) saturate(100%)",
                opacity: 0.9,
              }}
            />
          </div>
          <div style={{ flex: 1, paddingTop: 2 }}>
            <div
              style={{
                fontSize: 12,
                fontWeight: 600,
                color: colors.stone700,
                marginBottom: 6,
              }}
            >
              Claude
            </div>
            <div
              style={{
                fontSize: 15,
                color: colors.stone700,
                lineHeight: 1.45,
                maxWidth: 520,
              }}
            >
              I drafted this plan. Want a second pass from another agent before
              we seal it to the team?
            </div>
          </div>
        </div>

        <div
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: 8,
            padding: "8px 12px",
            borderRadius: 10,
            background: "rgba(255,255,255,0.7)",
            border: `1px solid ${colors.stone300}`,
            fontSize: 13,
            fontWeight: 600,
            color: colors.stone700,
            letterSpacing: "-0.02em",
            marginLeft: 40,
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

      {/* Claude-style input */}
      <div
        style={{
          padding: "10px 16px 16px",
          background: "#f5f0e8",
        }}
      >
        <div
          style={{
            borderRadius: 18,
            border: `1.5px solid ${doneTyping ? "#c4a484" : colors.stone300}`,
            background: "#fff",
            padding: "14px 14px 12px",
            boxShadow: doneTyping
              ? "0 0 0 3px rgba(196,164,132,0.25)"
              : "0 2px 8px rgba(28,25,23,0.04)",
          }}
        >
          <div
            style={{
              minHeight: 44,
              fontSize: 16,
              fontWeight: 500,
              color: colors.stone900,
              letterSpacing: "-0.02em",
              display: "flex",
              alignItems: "flex-start",
              marginBottom: 10,
            }}
          >
            {typed.length === 0 ? (
              <span style={{ color: colors.stone500, fontWeight: 400 }}>
                Reply to Claude…
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
                width: 36,
                height: 36,
                borderRadius: 99,
                background: doneTyping ? "#d97757" : colors.stone300,
                color: "#fff",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                fontSize: 16,
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
  );
};
