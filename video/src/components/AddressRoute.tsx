import React from "react";
import {
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { PARTICIPANT_ADDRESSES } from "../participants";
import { colors, FONT } from "../theme";
import { beats, routeHops } from "../timing";

const NODES = PARTICIPANT_ADDRESSES;

/** Vertical identity route — same cast as opening stack. */
export const AddressRoute: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { start, end } = beats.collab;

  const enter = spring({
    frame: Math.max(0, frame - start),
    fps,
    config: { damping: 14, stiffness: 120 },
  });
  const exit = interpolate(frame, [end - 24, end + 4], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  if (frame < start - 2 || exit < 0.02) return null;

  const activeTo = (() => {
    for (const hop of routeHops) {
      if (frame >= hop.start && frame < hop.end) return hop.to;
    }
    if (frame >= routeHops[2].end) return NODES[NODES.length - 1];
    return null;
  })();

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: 0,
        opacity: enter * exit,
        transform: `translateY(${(1 - enter) * 12}px)`,
        fontFamily: FONT,
        marginBottom: 14,
      }}
    >
      {NODES.map((node, i) => {
        const lit = activeTo === node || (activeTo === null && i === 0);
        const hopIn = routeHops.find((h) => h.to === node);
        const pulse = hopIn
          ? interpolate(
              frame,
              [hopIn.start, hopIn.start + 12, hopIn.end - 8, hopIn.end],
              [0, 1, 1, 0.35],
              { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
            )
          : lit
            ? 0.55
            : 0.25;

        const long = node.length > 12;

        return (
          <React.Fragment key={node}>
            <div
              style={{
                padding: long ? "8px 14px" : "10px 22px",
                borderRadius: 12,
                background: lit ? colors.accentSoft : "rgba(255,255,255,0.85)",
                border: `1.5px solid ${lit ? colors.accent : colors.stone300}`,
                fontSize: long ? 18 : 24,
                fontWeight: 650,
                letterSpacing: "-0.03em",
                color: lit ? colors.stone900 : colors.stone500,
                boxShadow: lit
                  ? `0 10px 28px -18px ${colors.accent}99`
                  : "0 6px 16px -14px rgba(28,25,23,0.25)",
                opacity: 0.45 + pulse * 0.55,
                transform: `scale(${0.96 + pulse * 0.06})`,
                maxWidth: 280,
                textAlign: "center",
              }}
            >
              {node}
            </div>
            {i < NODES.length - 1 ? (
              <div
                style={{
                  width: 2,
                  height: 16,
                  background: colors.stone300,
                  margin: "3px 0",
                  position: "relative",
                  overflow: "hidden",
                }}
              >
                {(() => {
                  const hop = routeHops[i];
                  if (!hop) return null;
                  const t = interpolate(frame, [hop.start, hop.end], [0, 1], {
                    extrapolateLeft: "clamp",
                    extrapolateRight: "clamp",
                  });
                  if (t <= 0 || t >= 1) return null;
                  return (
                    <div
                      style={{
                        position: "absolute",
                        left: -3,
                        top: `${t * 100}%`,
                        width: 8,
                        height: 8,
                        marginTop: -4,
                        borderRadius: 3,
                        background: colors.stone900,
                        opacity: interpolate(t, [0, 0.15, 0.85, 1], [0, 1, 1, 0]),
                      }}
                    />
                  );
                })()}
              </div>
            ) : null}
          </React.Fragment>
        );
      })}
    </div>
  );
};
