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
import { beats, threadBeats, DRAFT_FILENAME } from "../timing";
import { BrandId } from "./BrandMark";

type RowProps = {
  brand: BrandId;
  handle: string;
  body: React.ReactNode;
  appearAt: number;
  indent?: number;
};

const brandSrc: Partial<Record<BrandId, string>> = {
  claude: "hosts/claude.png",
  chatgpt: "hosts/chatgpt.png",
};

const avatarFor = (handle: string): BrandId => {
  if (handle === "@claude") return "claude";
  if (handle === "@cursor") return "cursor";
  if (handle.includes("openclaw")) return "openclaw";
  return "default";
};

const ThreadAvatar: React.FC<{ brand: BrandId; size?: number }> = ({
  brand,
  size = 32,
}) => {
  const src = brandSrc[brand];
  return (
    <div
      style={{
        width: size,
        height: size,
        borderRadius: size * 0.28,
        background: colors.stone200,
        border: `1px solid ${colors.stone300}`,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        flexShrink: 0,
      }}
    >
      {src ? (
        <Img
          src={staticFile(src)}
          style={{
            width: size * 0.55,
            height: size * 0.55,
            objectFit: "contain",
            filter: "brightness(0) saturate(100%)",
            opacity: 0.9,
          }}
        />
      ) : (
        <span style={{ fontSize: 11, fontWeight: 700, color: colors.stone700 }}>
          {brand.slice(0, 1).toUpperCase()}
        </span>
      )}
    </div>
  );
};

const ThreadRow: React.FC<RowProps> = ({
  brand,
  handle,
  body,
  appearAt,
  indent = 0,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({
    frame: Math.max(0, frame - appearAt),
    fps,
    config: { damping: 16, stiffness: 120 },
  });
  if (frame < appearAt - 1) return null;

  return (
    <div
      style={{
        marginLeft: indent,
        opacity: enter,
        transform: `translateY(${(1 - enter) * 16}px)`,
        marginBottom: 16,
      }}
    >
      <div style={{ display: "flex", gap: 12, alignItems: "flex-start" }}>
        <ThreadAvatar brand={brand} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div
            style={{
              fontSize: 14,
              fontWeight: 650,
              color: colors.accent,
              marginBottom: 6,
              letterSpacing: "-0.02em",
            }}
          >
            {handle}
          </div>
          <div
            style={{
              fontSize: 15,
              lineHeight: 1.4,
              color: colors.stone700,
              letterSpacing: "-0.015em",
            }}
          >
            {body}
          </div>
        </div>
      </div>
    </div>
  );
};

/** Nested thread — addresses stay visible; routing is the story. */
export const CollaborationThread: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { start, end } = beats.collab;

  const fadeIn = interpolate(frame, [start - 8, start + 20], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const fadeOut = interpolate(frame, [end - 20, end + 8], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  if (frame < start - 10 || fadeOut < 0.02) return null;

  const windowEnter = spring({
    frame: Math.max(0, frame - start),
    fps,
    config: { damping: 16, stiffness: 100 },
    durationInFrames: 28,
  });

  return (
    <div
      style={{
        width: 560,
        opacity: fadeOut * fadeIn * windowEnter,
        transform: `translateY(${(1 - windowEnter) * 18}px) scale(${0.97 + windowEnter * 0.03})`,
        fontFamily: FONT,
        borderRadius: 16,
        overflow: "hidden",
        background: colors.stone50,
        border: `1px solid ${colors.stone300}`,
        boxShadow:
          "0 36px 72px -28px rgba(28,25,23,0.42), 0 0 0 1px rgba(28,25,23,0.04)",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 10,
          padding: "11px 14px",
          background: colors.stone100,
          borderBottom: `1px solid ${colors.stone200}`,
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
            src={staticFile("brand/mt-mark.png")}
            style={{
              width: 18,
              height: 18,
              borderRadius: 5,
              objectFit: "cover",
            }}
          />
          <span
            style={{
              fontSize: 13,
              fontWeight: 600,
              color: colors.stone700,
              letterSpacing: "-0.02em",
            }}
          >
            mutande
          </span>
        </div>
        <div style={{ width: 52 }} />
      </div>

      <div
        style={{
          padding: "12px 20px 10px",
          borderBottom: `1px solid ${colors.stone200}`,
          background: "#fff",
        }}
      >
        <div
          style={{
            fontSize: 11,
            fontWeight: 600,
            letterSpacing: "0.06em",
            textTransform: "uppercase",
            color: colors.stone500,
            marginBottom: 4,
          }}
        >
          Thread
        </div>
        <div
          style={{
            fontSize: 15,
            fontWeight: 600,
            color: colors.stone900,
            letterSpacing: "-0.02em",
          }}
        >
          Critique before send
        </div>
      </div>

      <div
        style={{
          padding: "18px 20px 22px",
          background: "#fff",
          minHeight: 280,
        }}
      >
        <ThreadRow
          brand={avatarFor("@cursor")}
          handle="@cursor"
          appearAt={threadBeats.claudeAsk}
          body={
            <>
              <div style={{ marginBottom: 10 }}>
                Ask{" "}
                <span style={{ color: colors.accent, fontWeight: 650 }}>
                  bob@acme/openclaw
                </span>{" "}
                to critique before we send to the team.
              </div>
              <div
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: 8,
                  padding: "8px 11px",
                  borderRadius: 10,
                  background: colors.stone100,
                  border: `1px solid ${colors.stone300}`,
                  fontSize: 13,
                  fontWeight: 600,
                  color: colors.stone900,
                }}
              >
                <span
                  style={{
                    width: 9,
                    height: 11,
                    borderRadius: 2,
                    border: `1.5px solid ${colors.stone500}`,
                    opacity: 0.75,
                  }}
                />
                {DRAFT_FILENAME}
              </div>
            </>
          }
        />

        <ThreadRow
          brand={avatarFor("@claude")}
          handle="@claude"
          indent={28}
          appearAt={threadBeats.chatgptReply}
          body="Routing to bob@acme/openclaw — they'll mark what to tighten."
        />

        <ThreadRow
          brand={avatarFor("bob@acme/openclaw")}
          handle="bob@acme/openclaw"
          indent={56}
          appearAt={threadBeats.researchReply}
          body="Critique ready. Copy alice@acme/n8n-tickets when you seal."
        />

        {frame >= beats.seal.start ? (
          <div
            style={{
              marginTop: 16,
              marginLeft: 56,
              display: "inline-flex",
              alignItems: "center",
              gap: 10,
              padding: "10px 14px",
              borderRadius: 12,
              background: colors.stone100,
              border: `1.5px solid ${colors.accent}55`,
              opacity: interpolate(
                frame,
                [beats.seal.start, beats.seal.start + 14],
                [0, 1],
                { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
              ),
              transform: `translateY(${interpolate(
                frame,
                [beats.seal.start, beats.seal.start + 14],
                [8, 0],
                { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
              )}px)`,
            }}
          >
            <span
              style={{
                width: 14,
                height: 16,
                borderRadius: 3,
                border: `2px solid ${colors.accent}`,
                opacity: 0.85,
              }}
            />
            <span
              style={{
                fontSize: 13,
                fontWeight: 650,
                letterSpacing: "-0.02em",
                color: colors.stone900,
              }}
            >
              {DRAFT_FILENAME}
            </span>
            <span
              style={{
                fontSize: 10,
                fontWeight: 700,
                letterSpacing: "0.08em",
                textTransform: "uppercase",
                color: colors.accent,
              }}
            >
              sealed
            </span>
          </div>
        ) : null}
      </div>
    </div>
  );
};
