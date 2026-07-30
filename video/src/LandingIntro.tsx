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
import { getCameraPose } from "./camera";
import { AgentOrb } from "./components/AgentOrb";
import { AgentsBridge } from "./components/AgentsBridge";
import { CollaborationThread } from "./components/CollaborationThread";
import { DocSheets } from "./components/DocSheets";
import { EncryptedTransit } from "./components/EncryptedTransit";
import { ComposeWindow } from "./components/ComposeWindow";
import { EnvPlate } from "./components/EnvPlate";
import { RECIPIENTS, SENDER_HANDLE } from "./recipients";
import { colors, FONT } from "./theme";
import { beats, critiquePasses } from "./timing";

const passIntensity = (frame: number, index: number) => {
  const p = critiquePasses[index];
  if (frame < p.start || frame >= p.end) return 0;
  return Math.sin(
    interpolate(frame, [p.start, p.end], [0, Math.PI], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    }),
  );
};

export const LandingIntro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pose = getCameraPose(frame);

  const scene =
    frame < beats.compose.end
      ? "compose"
      : frame < beats.finalDoc.start
        ? "critique"
        : frame < beats.transit.start
          ? "doc"
          : frame < beats.hold.start
            ? "transit"
            : "hold";

  const composeOpacity = interpolate(
    frame,
    [0, 12, beats.compose.end - 36, beats.compose.end],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  const agentWorldOpacity = interpolate(
    frame,
    [beats.compose.end - 40, beats.critique.start + 12],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  const finalize = interpolate(
    frame,
    [beats.finalDoc.start, beats.finalDoc.start + 70],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  // Wide-shot layout (used once camera pulls back)
  const wide = spring({
    frame: Math.max(0, frame - beats.transit.start),
    fps,
    config: { damping: 16, stiffness: 70 },
    durationInFrames: 55,
  });

  const aliceWidth = interpolate(wide, [0, 1], [100, 38]);
  const aliceLeft = interpolate(wide, [0, 1], [0, 2]);
  const fanOpacity = interpolate(wide, [0.05, 0.4], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const fanLeft = interpolate(wide, [0, 1], [100, 52]);
  const fanWidth = interpolate(wide, [0, 1], [0, 46]);

  const docLift = interpolate(
    frame,
    [beats.finalDoc.start + 50, beats.transit.start - 4],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  const showDocInAlice =
    scene === "doc" && docLift < 0.92;

  const receiveDoc = interpolate(
    frame,
    [beats.transit.start + 160, beats.transit.start + 220],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  const receivePop = spring({
    frame: Math.max(0, frame - (beats.transit.start + 170)),
    fps,
    config: { damping: 11, stiffness: 170 },
  });

  const fromToOpacity = interpolate(
    frame,
    [
      beats.transit.start + 40,
      beats.transit.start + 70,
      beats.transit.end - 50,
      beats.transit.end - 10,
    ],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  const hold = interpolate(
    frame,
    [beats.hold.start, beats.hold.start + 36],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  const sceneFade = 1 - hold * 0.94;

  const inCollab = scene === "critique";

  const docScale =
    scene === "doc"
      ? interpolate(
          frame,
          [beats.finalDoc.start, beats.finalDoc.start + 60],
          [1.35, 1.55],
          { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
        )
      : interpolate(wide, [0, 1], [1.1, 0.65]);

  const i0 = passIntensity(frame, 0);
  const i1 = passIntensity(frame, 1);
  const i2 = passIntensity(frame, 2);
  const claudeActive = i0 > 0.05 || i2 > 0.05;
  const chatgptActive = i1 > 0.05 || (i2 > 0.05 && i2 < 0.85);

  // Alice chrome only on wide / handover
  const aliceChrome = interpolate(wide, [0.15, 0.55], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const hugChrome = aliceChrome > 0.2 || scene === "transit";

  const orbsOpacity = scene === "doc" || scene === "transit" ? 1 : 0;
  const aliceOrbSize = interpolate(wide, [0, 1], [72, 44]);

  return (
    <AbsoluteFill
      style={{
        backgroundColor: colors.stone50,
        backgroundImage: `
          radial-gradient(ellipse 70% 50% at 80% 20%, ${colors.accent}1a, transparent 60%),
          radial-gradient(ellipse 50% 40% at 20% 80%, ${colors.stone200}88, transparent 55%)
        `,
        fontFamily: FONT,
        overflow: "hidden",
      }}
    >
      {/* Compose window — typing scene */}
      <AbsoluteFill
        style={{
          justifyContent: "center",
          alignItems: "center",
          opacity: composeOpacity * sceneFade,
          pointerEvents: "none",
          zIndex: 2,
        }}
      >
        <ComposeWindow />
      </AbsoluteFill>

      {/* Cinematic stage — camera scale/pan */}
      <AbsoluteFill
        style={{
          opacity: sceneFade * agentWorldOpacity,
          transform: `translate(${pose.x}%, ${pose.y}%) scale(${pose.scale})`,
          transformOrigin: "50% 45%",
        }}
      >
        <div
          style={{
            position: "absolute",
            top: 0,
            bottom: 0,
            left: `${aliceLeft}%`,
            width: `${aliceWidth}%`,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            padding: hugChrome || inCollab ? 12 : 24,
          }}
        >
          {inCollab ||
          (frame >= beats.critique.start &&
            frame < beats.finalDoc.start + 40 &&
            wide < 0.5) ? (
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <AgentsBridge />
              <CollaborationThread />
            </div>
          ) : (
            <EnvPlate
              title="Alice"
              accent={colors.alice}
              chrome={aliceChrome}
              hug={hugChrome}
              dimmed={docLift > 0.85 && wide > 0.85}
            >
              <div
                style={{
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  justifyContent: "center",
                  gap: 14,
                }}
              >
                <div
                  style={{
                    display: "flex",
                    gap: 28,
                    alignItems: "flex-start",
                    opacity: orbsOpacity,
                  }}
                >
                  <AgentOrb
                    brand="claude"
                    label="@claude"
                    accent={colors.alice}
                    active={claudeActive && frame < beats.transit.start}
                    intensity={Math.max(i0, i2 * 0.7)}
                    size={aliceOrbSize}
                  />
                  <AgentOrb
                    brand="chatgpt"
                    label="@chatgpt"
                    accent={colors.amber}
                    active={chatgptActive && frame < beats.transit.start}
                    intensity={i1}
                    size={aliceOrbSize}
                  />
                </div>

                {showDocInAlice ? (
                  <div
                    style={{
                      transform:
                        scene === "doc"
                          ? `scale(${1 + finalize * 0.06})`
                          : undefined,
                    }}
                  >
                    <DocSheets
                      finalize={finalize}
                      lift={docLift}
                      scale={docScale}
                      critique={finalize < 1}
                    />
                  </div>
                ) : null}
              </div>
            </EnvPlate>
          )}
        </div>

        {/* Fan-out — only meaningful once pulled wide */}
        <div
          style={{
            position: "absolute",
            top: 0,
            bottom: 0,
            left: `${fanLeft}%`,
            width: `${Math.max(fanWidth, 0.01)}%`,
            opacity: fanOpacity,
            display: "flex",
            flexDirection: "column",
            alignItems: "stretch",
            justifyContent: "center",
            gap: 14,
            padding: "24px 16px",
          }}
        >
          {RECIPIENTS.map((r, index) => {
            const stagger = spring({
              frame: Math.max(0, frame - beats.transit.start - 8 - index * 10),
              fps,
              config: { damping: 14, stiffness: 120 },
            });
            return (
              <div
                key={r.id}
                style={{
                  opacity: stagger,
                  transform: `translateX(${(1 - stagger) * 40}px)`,
                }}
              >
                <EnvPlate title={r.title} accent={r.accent} hug>
                  <div
                    style={{
                      display: "flex",
                      alignItems: "center",
                      gap: 16,
                      minWidth: 260,
                    }}
                  >
                    <AgentOrb
                      brand={r.brand}
                      label={r.label}
                      accent={r.accent}
                      active={receiveDoc > 0.35}
                      intensity={receiveDoc}
                      size={40}
                    />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div
                        style={{
                          fontSize: 12,
                          fontWeight: 600,
                          color: colors.stone700,
                          letterSpacing: "-0.01em",
                          marginBottom: 6,
                        }}
                      >
                        {r.handle}
                      </div>
                      <div
                        style={{
                          opacity: receiveDoc,
                          transform: `scale(${0.5 + receivePop * 0.5})`,
                          transformOrigin: "left center",
                          filter:
                            receiveDoc > 0.2 && receiveDoc < 0.95
                              ? `drop-shadow(0 0 ${12 * receivePop}px ${r.accent})`
                              : undefined,
                        }}
                      >
                        <DocSheets finalize={1} lift={0} scale={0.42} />
                      </div>
                    </div>
                  </div>
                </EnvPlate>
              </div>
            );
          })}
        </div>

        {frame >= beats.transit.start - 10 && frame < beats.hold.start ? (
          <EncryptedTransit />
        ) : null}

        <div
          style={{
            position: "absolute",
            bottom: "3%",
            left: 0,
            right: 0,
            display: "flex",
            justifyContent: "center",
            opacity: fromToOpacity,
            padding: "0 24px",
          }}
        >
          <div
            style={{
              display: "flex",
              flexWrap: "wrap",
              alignItems: "center",
              justifyContent: "center",
              gap: 8,
              padding: "12px 16px",
              borderRadius: 14,
              background: "rgba(255,255,255,0.92)",
              border: `1px solid ${colors.border}`,
              fontSize: 13,
              color: colors.stone700,
              fontWeight: 600,
              boxShadow: "0 10px 28px -18px rgba(28,25,23,0.4)",
              maxWidth: 920,
            }}
          >
            <span>{SENDER_HANDLE}</span>
            <span style={{ color: colors.accent, fontWeight: 700 }}>→</span>
            {RECIPIENTS.map((r, i) => (
              <React.Fragment key={r.id}>
                {i > 0 ? (
                  <span style={{ opacity: 0.35, fontWeight: 500 }}>·</span>
                ) : null}
                <span>{r.handle}</span>
              </React.Fragment>
            ))}
          </div>
        </div>
      </AbsoluteFill>

      <AbsoluteFill
        style={{
          justifyContent: "center",
          alignItems: "center",
          opacity: hold,
          backgroundColor:
            hold > 0.05 ? `rgba(250,249,247,${hold * 0.94})` : "transparent",
        }}
      >
        <Img
          src={staticFile("brand/mt-mark.png")}
          style={{
            width: 260,
            height: 260,
            borderRadius: 28,
            boxShadow: "0 24px 60px -28px rgba(28,25,23,0.55)",
            transform: `scale(${0.86 + hold * 0.14})`,
          }}
        />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
