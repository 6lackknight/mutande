import React from "react";
import {
  AbsoluteFill,
  Img,
  interpolate,
  staticFile,
  useCurrentFrame,
} from "remotion";
import { getCameraPose } from "./camera";
import { AddressRoute } from "./components/AddressRoute";
import { CollaborationThread } from "./components/CollaborationThread";
import { ComposeWindow } from "./components/ComposeWindow";
import { EncryptedTransit } from "./components/EncryptedTransit";
import { ExplainerCard } from "./components/ExplainerCard";
import { IdentityTree } from "./components/IdentityTree";
import { colors, FONT } from "./theme";
import { beats, explainers } from "./timing";

export const LandingIntro: React.FC = () => {
  const frame = useCurrentFrame();
  const pose = getCameraPose(frame);

  const scene =
    frame < beats.identity.end
      ? "identity"
      : frame < beats.compose.end
        ? "compose"
        : frame < beats.explain.end
          ? "explain"
          : frame < beats.collab.end
            ? "collab"
            : frame < beats.handoff.end
              ? "handoff"
              : frame < beats.fanout.end
                ? "fanout"
                : "hold";

  const identityOpacity = interpolate(
    frame,
    [0, 14, beats.identity.end - 36, beats.identity.end],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  const composeOpacity = interpolate(
    frame,
    [
      beats.compose.start,
      beats.compose.start + 14,
      beats.compose.end - 28,
      beats.compose.end,
    ],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  const inProduct =
    scene === "collab" || scene === "handoff" || scene === "fanout";
  const productOpacity = inProduct
    ? interpolate(
        frame,
        scene === "collab"
          ? [
              beats.collab.start - 8,
              beats.collab.start + 16,
              beats.collab.end - 18,
              beats.collab.end,
            ]
          : [
              beats.handoff.start,
              beats.handoff.start + 16,
              beats.fanout.end - 28,
              beats.fanout.end,
            ],
        [0, 1, 1, 0],
        { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
      )
    : 0;

  const hold = interpolate(
    frame,
    [beats.hold.start, beats.hold.start + 40],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  const sceneFade = 1 - hold * 0.96;

  // Loop seam: soft fade at the very end so restart into identity is clean
  const loopOut = interpolate(
    frame,
    [DURATION_NEAR_END, beats.hold.end],
    [1, 0.92],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <AbsoluteFill
      style={{
        backgroundColor: colors.stone50,
        backgroundImage: `
          radial-gradient(ellipse 70% 50% at 80% 20%, ${colors.accent}14, transparent 60%),
          radial-gradient(ellipse 50% 40% at 20% 80%, ${colors.stone200}88, transparent 55%)
        `,
        fontFamily: FONT,
        overflow: "hidden",
        opacity: loopOut,
      }}
    >
      {/* 1. Identity */}
      <AbsoluteFill
        style={{
          justifyContent: "center",
          alignItems: "center",
          opacity: identityOpacity * sceneFade,
          pointerEvents: "none",
          zIndex: 2,
          transform: `translate(${pose.x}%, ${pose.y}%) scale(${pose.scale})`,
          transformOrigin: "50% 45%",
          padding: "0 80px",
        }}
      >
        <IdentityTree />
      </AbsoluteFill>

      {/* 2. Compose */}
      <AbsoluteFill
        style={{
          justifyContent: "center",
          alignItems: "center",
          opacity: composeOpacity * sceneFade,
          pointerEvents: "none",
          zIndex: 2,
          transform: `translate(${pose.x}%, ${pose.y}%) scale(${pose.scale})`,
          transformOrigin: "50% 45%",
        }}
      >
        <ComposeWindow />
      </AbsoluteFill>

      {/* 4–6. Collab + handoff + fan-out stage */}
      <AbsoluteFill
        style={{
          opacity: sceneFade * productOpacity,
          transform: `translate(${pose.x}%, ${pose.y}%) scale(${pose.scale})`,
          transformOrigin: "50% 50%",
        }}
      >
        {scene === "collab" ? (
          <div
            style={{
              position: "absolute",
              inset: 0,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              gap: 36,
              padding: 32,
            }}
          >
            <AddressRoute />
            <CollaborationThread />
          </div>
        ) : null}

        {(scene === "handoff" || scene === "fanout") && frame < beats.fanout.end ? (
          <EncryptedTransit />
        ) : null}
      </AbsoluteFill>

      {/* 3. Explainer */}
      {explainers.map((e) => (
        <ExplainerCard key={e.id} text={e.text} start={e.start} end={e.end} />
      ))}

      {/* 7. Brand close */}
      <AbsoluteFill
        style={{
          justifyContent: "center",
          alignItems: "center",
          opacity: hold,
          backgroundColor:
            hold > 0.05 ? `rgba(250,249,247,${hold * 0.96})` : "transparent",
          fontFamily: FONT,
        }}
      >
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 22,
            transform: `scale(${0.9 + hold * 0.1})`,
          }}
        >
          <div
            style={{
              fontSize: 72,
              fontWeight: 700,
              letterSpacing: "-0.06em",
              color: colors.accent,
              lineHeight: 1,
            }}
          >
            @i
          </div>
          <div
            style={{
              fontSize: 36,
              fontWeight: 600,
              letterSpacing: "-0.035em",
              color: colors.stone900,
              lineHeight: 1.15,
            }}
          >
            Address Intelligence.
          </div>
          <Img
            src={staticFile("brand/mt-mark.png")}
            style={{
              width: 120,
              height: 120,
              borderRadius: 22,
              marginTop: 12,
              boxShadow: "0 20px 48px -24px rgba(28,25,23,0.5)",
            }}
          />
          <div
            style={{
              fontSize: 42,
              fontWeight: 650,
              letterSpacing: "-0.04em",
              color: colors.stone900,
              lineHeight: 1,
            }}
          >
            mutande
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const DURATION_NEAR_END = beats.hold.end - 24;
