"use client";

import {
  useEffect,
  useRef,
  useState,
  type ReactNode,
  type RefObject,
} from "react";
import type { ForceFieldInstance } from "@/components/canvas-ui/force-field";

type FieldTier = "desktop" | "mobile";

/** Network Information API — not in lib.dom for all TS targets. */
type NetworkConnection = { saveData?: boolean };

function fieldTier(): FieldTier | null {
  if (typeof window === "undefined") return null;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    return null;
  }
  const connection = (
    navigator as Navigator & { connection?: NetworkConnection }
  ).connection;
  if (connection?.saveData) return null;
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
    captureContent: false as const,
  };
}

/** WebGL lattice overlay — mounts over stable page content without remounting it. */
function LandingForceFieldOverlay({
  shellRef,
  tier,
}: {
  shellRef: RefObject<HTMLDivElement | null>;
  tier: FieldTier;
}) {
  const sourceRef = useRef<HTMLCanvasElement>(null);
  const outputRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const shell = shellRef.current;
    const source = sourceRef.current;
    const output = outputRef.current;
    if (!shell || !source || !output) return;

    let instance: ForceFieldInstance | null = null;
    let cancelled = false;

    void import("@/components/canvas-ui/force-field").then(
      ({ createForceField }) => {
        if (cancelled) return;
        instance = createForceField(
          { source, content: shell, output },
          fieldProps(tier),
        );
      },
    );

    return () => {
      cancelled = true;
      instance?.destroy();
    };
  }, [shellRef, tier]);

  return (
    <>
      <canvas ref={sourceRef} aria-hidden style={{ display: "none" }} />
      <canvas
        ref={outputRef}
        aria-hidden
        className="pointer-events-none absolute inset-0 h-full w-full"
      />
    </>
  );
}

/**
 * Muted Force Field over the landing shell. Content stays in one stable wrapper
 * for LCP; the lattice overlay is deferred a beat so PSI sees paint first.
 */
export function LandingForceField({ children }: { children: ReactNode }) {
  const shellRef = useRef<HTMLDivElement>(null);
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

  return (
    <div
      ref={shellRef}
      className="relative flex min-h-full flex-1 flex-col"
      style={{ minHeight: "100%" }}
    >
      {children}
      {tier ? (
        <LandingForceFieldOverlay shellRef={shellRef} tier={tier} />
      ) : null}
    </div>
  );
}
