import React from "react";
import { interpolate, spring, useVideoConfig } from "remotion";

type Props = {
  id: string;
  /** Pixel coords inside the SVG viewBox */
  from: { x: number; y: number };
  to: { x: number; y: number };
  /** Vertical control-point offset (Magic UI `curvature`) */
  curvature?: number;
  reverse?: boolean;
  pathColor?: string;
  pathWidth?: number;
  pathOpacity?: number;
  gradientStartColor?: string;
  gradientStopColor?: string;
  /** Local frame for this beam’s cycle */
  frame: number;
  /** Cycle length in frames (~Magic UI duration*fps) */
  durationInFrames?: number;
  delayInFrames?: number;
  width: number;
  height: number;
  opacity?: number;
};

/**
 * Remotion port of Magic UI Animated Beam —
 * path + traveling gradient, sprung each cycle (ease-out settle).
 * @see https://magicui.design/docs/components/animated-beam
 */
export const AnimatedBeam: React.FC<Props> = ({
  id,
  from,
  to,
  curvature = 0,
  reverse = false,
  pathColor = "#8a8478",
  pathWidth = 2,
  pathOpacity = 0.22,
  gradientStartColor = "#d4a24c",
  gradientStopColor = "#8b5a2b",
  frame,
  durationInFrames = 90,
  delayInFrames = 0,
  width,
  height,
  opacity = 1,
}) => {
  const { fps } = useVideoConfig();
  const controlY = from.y - curvature;
  const d = `M ${from.x},${from.y} Q ${(from.x + to.x) / 2},${controlY} ${to.x},${to.y}`;

  const local = Math.max(0, frame - delayInFrames);
  // Travel most of the cycle, then hold so the spring settle reads
  const travelFrames = Math.floor(durationInFrames * 0.72);
  const cycle = ((local % durationInFrames) + durationInFrames) % durationInFrames;

  const t = spring({
    frame: Math.min(cycle, travelFrames),
    fps,
    config: { damping: 16, stiffness: 55, mass: 0.85 },
    durationInFrames: travelFrames,
  });

  // Magic UI: gradient window slides along the path
  const x1 = reverse
    ? interpolate(t, [0, 1], [90, -10])
    : interpolate(t, [0, 1], [10, 110]);
  const x2 = reverse
    ? interpolate(t, [0, 1], [100, 0])
    : interpolate(t, [0, 1], [0, 100]);

  const appear = spring({
    frame: local,
    fps,
    config: { damping: 18, stiffness: 120 },
    durationInFrames: 22,
  });

  // Soft fade at cycle seam so the restart isn’t a hard cut
  const seamFade = interpolate(
    cycle,
    [durationInFrames - 10, durationInFrames - 1],
    [1, 0.35],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      style={{
        position: "absolute",
        inset: 0,
        pointerEvents: "none",
        opacity: opacity * appear,
        overflow: "visible",
      }}
    >
      <path
        d={d}
        stroke={pathColor}
        strokeWidth={pathWidth}
        strokeOpacity={pathOpacity}
        fill="none"
        strokeLinecap="round"
      />
      <path
        d={d}
        stroke={`url(#${id})`}
        strokeWidth={pathWidth + 0.5}
        fill="none"
        strokeLinecap="round"
        opacity={seamFade}
      />
      <defs>
        <linearGradient
          id={id}
          gradientUnits="userSpaceOnUse"
          x1={`${x1}%`}
          x2={`${x2}%`}
          y1="0%"
          y2="0%"
        >
          <stop offset="0%" stopColor={gradientStartColor} stopOpacity={0} />
          <stop offset="32%" stopColor={gradientStartColor} stopOpacity={1} />
          <stop offset="62%" stopColor={gradientStopColor} stopOpacity={1} />
          <stop offset="100%" stopColor={gradientStopColor} stopOpacity={0} />
        </linearGradient>
      </defs>
    </svg>
  );
};
