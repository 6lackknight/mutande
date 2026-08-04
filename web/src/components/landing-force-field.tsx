"use client";

import type { ReactNode } from "react";
import { ForceField } from "@/components/canvas-ui/force-field";

/**
 * Muted Force Field over the landing shell — stone/bronze lattice, hover reveal,
 * no click ripples so CTAs stay readable.
 */
export function LandingForceField({ children }: { children: ReactNode }) {
  return (
    <ForceField
      className="flex min-h-full flex-1 flex-col"
      style={{ minHeight: "100%" }}
      shape="hexagon"
      // Bronze / amber (mutande accent), not cyan demo defaults
      color={[0.57, 0.25, 0.06]}
      edgeColor={[0.9, 0.65, 0.28]}
      opacity={0.38}
      cellScale={18}
      lineWidth={0.022}
      gridOpacity={0.05}
      gridReveal="hover"
      gridRevealStrength={0.85}
      gridRevealRadius={280}
      gridFade={0.45}
      flashSpeed={0.35}
      flashIntensity={0.04}
      flowScale={2.8}
      flowSpeed={0.28}
      flowIntensity={0.12}
      edgeGlow={0.14}
      edgeFalloff={0.22}
      clickRipples={false}
      refraction={6}
      aberration={0.4}
      haze={0.12}
      tint={0.03}
      hoverGlow={0.12}
      hoverRadius={320}
      hoverCharge={0.55}
      bloom={0.35}
      bloomThreshold={0.45}
      grain={0.06}
      dim={0}
      pageReact={0}
    >
      {children}
    </ForceField>
  );
}
