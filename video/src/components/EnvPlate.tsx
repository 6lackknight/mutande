import React from "react";
import { colors, FONT } from "../theme";

type Props = {
  title: string;
  accent: string;
  children: React.ReactNode;
  dimmed?: boolean;
  style?: React.CSSProperties;
  /** 0 = bare stage (no border/set), 1 = full env plate */
  chrome?: number;
  /** Size to contents with moderate padding (vs stretching fill) */
  hug?: boolean;
};

export const EnvPlate: React.FC<Props> = ({
  title,
  accent,
  children,
  dimmed = false,
  style,
  chrome = 1,
  hug = false,
}) => {
  const c = Math.max(0, Math.min(1, chrome));

  return (
    <div
      style={{
        position: "relative",
        borderRadius: 28,
        overflow: "hidden",
        opacity: dimmed ? 0.55 : 1,
        fontFamily: FONT,
        width: hug ? "fit-content" : undefined,
        maxWidth: hug ? "100%" : undefined,
        height: hug ? "fit-content" : undefined,
        ...style,
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: 28,
          border: `1.5px solid ${colors.border}`,
          background: `linear-gradient(165deg, ${colors.surface}, ${colors.stone100})`,
          boxShadow: `0 18px 40px -24px rgba(28,25,23,0.45), inset 0 0 0 1px ${accent}22`,
          opacity: c,
          pointerEvents: "none",
        }}
      />
      <div
        style={{
          position: "absolute",
          top: 0,
          left: 0,
          right: 0,
          height: 3,
          background: `linear-gradient(90deg, ${accent}, ${accent}55)`,
          opacity: c,
          pointerEvents: "none",
        }}
      />
      <div
        style={{
          position: "relative",
          zIndex: 1,
          display: "flex",
          flexDirection: "column",
          height: hug ? undefined : "100%",
        }}
      >
        <div
          style={{
            padding: c > 0.05 ? "12px 22px 6px" : "0",
            fontSize: 12,
            fontWeight: 600,
            letterSpacing: "0.04em",
            textTransform: "uppercase",
            color: colors.stone500,
            opacity: c,
            maxHeight: c > 0.05 ? 40 : 0,
            overflow: "hidden",
          }}
        >
          {title}
        </div>
        <div
          style={{
            flex: hug ? undefined : 1,
            padding: c > 0.05 ? "10px 28px 28px" : "8px 12px 16px",
            minHeight: 0,
          }}
        >
          {children}
        </div>
      </div>
    </div>
  );
};
