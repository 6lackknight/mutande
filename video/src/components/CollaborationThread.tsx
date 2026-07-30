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
import { beats, critiquePasses, DRAFT_FILENAME } from "../timing";
import { BrandId } from "./BrandMark";

type RowProps = {
  brand: BrandId;
  handle: string;
  body: React.ReactNode;
  appearAt: number;
  indent?: number;
  children?: React.ReactNode;
};

const brandSrc: Partial<Record<BrandId, string>> = {
  claude: "hosts/claude.png",
  chatgpt: "hosts/chatgpt.png",
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
  children,
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
              fontSize: 13,
              fontWeight: 600,
              color: colors.stone900,
              marginBottom: 6,
              letterSpacing: "-0.01em",
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
          {children}
        </div>
      </div>
    </div>
  );
};

/** Nested mutande-style thread for the collaboration beat. */
export const CollaborationThread: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const fadeOut = interpolate(
    frame,
    [beats.finalDoc.start - 16, beats.finalDoc.start + 36],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  if (frame < beats.critique.start - 4 || fadeOut < 0.02) return null;

  // After Claude's follow-up — ChatGPT upvotes (last beat)
  const upvoteAt = Math.min(
    critiquePasses[2].start + 90,
    beats.critique.end - 40,
  );
  const upvote = spring({
    frame: Math.max(0, frame - upvoteAt),
    fps,
    config: { damping: 12, stiffness: 160 },
  });

  const windowEnter = spring({
    frame: Math.max(0, frame - beats.critique.start),
    fps,
    config: { damping: 16, stiffness: 100 },
    durationInFrames: 28,
  });

  return (
    <div
      style={{
        width: 640,
        opacity: fadeOut * windowEnter,
        transform: `translateY(${(1 - windowEnter) * 24}px) scale(${0.96 + windowEnter * 0.04})`,
        fontFamily: FONT,
        borderRadius: 16,
        overflow: "hidden",
        background: colors.stone50,
        border: `1px solid ${colors.stone300}`,
        boxShadow:
          "0 36px 72px -28px rgba(28,25,23,0.42), 0 0 0 1px rgba(28,25,23,0.04)",
      }}
    >
      {/* mutande title bar */}
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

      {/* Thread header */}
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

      {/* Nested replies */}
      <div
        style={{
          padding: "18px 20px 22px",
          background: "#fff",
          minHeight: 320,
        }}
      >
        {/* 1. Initial request + attachment */}
        <ThreadRow
          brand="claude"
          handle="@claude"
          appearAt={critiquePasses[0].start}
          body={
            <>
              <div style={{ marginBottom: 10 }}>
                ask @chatgpt to critique before we send to the team
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

        {/* 2. ChatGPT reply */}
        <ThreadRow
          brand="chatgpt"
          handle="@chatgpt"
          indent={28}
          appearAt={critiquePasses[1].start}
          body="Happy to help — I've marked the sections to tighten and trimmed the fluff."
        />

        {/* 3. Claude follow-up + 4. ChatGPT upvote */}
        <ThreadRow
          brand="claude"
          handle="@claude"
          indent={56}
          appearAt={critiquePasses[2].start}
          body={`Applied — sealing ${DRAFT_FILENAME} now.`}
        >
          <div
            style={{
              marginTop: 12,
              display: "inline-flex",
              alignItems: "center",
              gap: 6,
              padding: "6px 11px",
              borderRadius: 8,
              background:
                upvote > 0.25 ? colors.accentSoft : colors.stone100,
              border: `1px solid ${upvote > 0.25 ? colors.accent : colors.stone300}`,
              fontSize: 12,
              fontWeight: 600,
              color: upvote > 0.25 ? colors.accent : colors.stone500,
              opacity: Math.max(0.12, upvote),
              transform: `scale(${0.85 + upvote * 0.15})`,
              transformOrigin: "left center",
            }}
          >
            <span style={{ fontSize: 13, lineHeight: 1 }}>▲</span>
            <span>{upvote > 0.5 ? "1" : "0"}</span>
            <span style={{ fontWeight: 500, opacity: 0.75 }}>@chatgpt</span>
          </div>
        </ThreadRow>
      </div>
    </div>
  );
};
