"use client";

import dynamic from "next/dynamic";
import { useEffect, useState, type ReactNode } from "react";

const ForceField = dynamic(
  () =>
    import("@/components/canvas-ui/force-field").then((m) => m.ForceField),
  { ssr: false },
);

type FieldTier = "desktop" | "mobile";

function fieldTier(): FieldTier | null {
  if (typeof window === "undefined") return null;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    return null;
  }
  if (navigator.connection?.saveData) return null;
  if (window.matchMedia("(max-width: 767px), (pointer: coarse)").matches) {
    return "mobile";
  }
  return "desktop";
}

/** Shared bronze/amber lattice — lighter on mobile, fuller on desktop. */
function fieldProps(tier: FieldTier) {
  const mobile = tier === "mobile";
  return {
    shape: "hexagon" as const,
    // Bronze / amber (mutande accent), not cyan demo defaults
    color: [0.57, 0.25, 0.06] as [number, number, number],
    edgeColor: [0.9, 0.65, 0.28] as [number, number, number],
    opacity: mobile ? 0.32 : 0.38,
    cellScale: mobile ? 12 : 18,
    lineWidth: 0.022,
    gridOpacity: mobile ? 0.045 : 0.05,
    gridReveal: (mobile ? "always" : "hover") as "always" | "hover",
    gridRevealStrength: mobile ? 0.55 : 0.85,
    gridRevealRadius: 280,
    gridFade: 0.45,
    flashSpeed: mobile ? 0.22 : 0.35,
    flashIntensity: mobile ? 0.03 : 0.04,
    flowScale: 2.8,
    flowSpeed: mobile ? 0.2 : 0.28,
    flowIntensity: mobile ? 0.1 : 0.12,
    edgeGlow: mobile ? 0.12 : 0.14,
    edgeFalloff: 0.22,
    clickRipples: false,
    refraction: mobile ? 3 : 6,
    aberration: mobile ? 0.2 : 0.4,
    haze: mobile ? 0.08 : 0.12,
    tint: 0.03,
    hoverGlow: mobile ? 0 : 0.12,
    hoverRadius: 320,
    hoverCharge: mobile ? 0 : 0.55,
    bloom: mobile ? 0.15 : 0.35,
    bloomThreshold: 0.45,
    grain: mobile ? 0.05 : 0.06,
    dim: 0,
    pageReact: 0,
  };
}

/**
 * Muted Force Field over the landing shell. Deferred a beat past first paint
 * for LCP, then wraps content so the lattice composites correctly (not under
 * the opaque relay background).
 */
export function LandingForceField({ children }: { children: ReactNode }) {
  const [tier, setTier] = useState<FieldTier | null>(null);

  useEffect(() => {
    const next = fieldTier();
    if (!next) return;

    let cancelled = false;
    const delay = next === "mobile" ? 1800 : 600;
    const t = window.setTimeout(() => {
      if (!cancelled) setTier(next);
    }, delay);

    return () => {
      cancelled = true;
      window.clearTimeout(t);
    };
  }, []);

  if (!tier) {
    return (
      <div
        className="flex min-h-full flex-1 flex-col"
        style={{ minHeight: "100%" }}
      >
        {children}
      </div>
    );
  }

  return (
    <ForceField
      className="flex min-h-full flex-1 flex-col"
      style={{ minHeight: "100%" }}
      {...fieldProps(tier)}
    >
      {children}
    </ForceField>
  );
}
