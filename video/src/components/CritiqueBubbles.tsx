import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { colors } from "../theme";
import { beats, critiquePasses, DRAFT_FILENAME } from "../timing";
import { ChatBubble } from "./ChatBubble";

/** Critique loop — cinematic mode = one hero bubble dominates the frame. */
export const CritiqueBubbles: React.FC<{
  compact?: boolean;
  cinematic?: boolean;
}> = ({ compact = false, cinematic = false }) => {
  const frame = useCurrentFrame();
  const fadeOut = interpolate(
    frame,
    [beats.handoff.start - 20, beats.handoff.start + 40],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  if (frame < beats.critique.start - 4 || fadeOut < 0.02) return null;

  const w = cinematic ? 560 : compact ? 200 : 300;

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        gap: cinematic ? 22 : compact ? 10 : 14,
        width: cinematic ? 640 : compact ? "92%" : Math.min(420, w + 140),
        opacity: fadeOut,
        marginTop: cinematic ? 20 : 8,
        marginBottom: cinematic ? 8 : 4,
      }}
    >
      <ChatBubble
        side="left"
        accent={colors.alice}
        text={`@chatgpt — critique ${DRAFT_FILENAME} before we send?`}
        appearAt={critiquePasses[0].start}
        disappearAt={critiquePasses[1].start + 12}
        maxWidth={w}
        cinematic={cinematic}
      />
      <ChatBubble
        side="right"
        accent={colors.amber}
        text="Happy to help — I've marked the sections to tighten and trimmed the fluff."
        appearAt={critiquePasses[1].start}
        disappearAt={critiquePasses[2].start + 12}
        maxWidth={w}
        cinematic={cinematic}
      />
      <ChatBubble
        side="left"
        accent={colors.alice}
        text={`Yes — applied. Sealing ${DRAFT_FILENAME} now.`}
        appearAt={critiquePasses[2].start}
        disappearAt={beats.handoff.start + 50}
        maxWidth={w}
        cinematic={cinematic}
      />
    </div>
  );
};
