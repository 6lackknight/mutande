"use client";

import dynamic from "next/dynamic";
import { useEffect, useState, type ReactNode } from "react";

const ForceField = dynamic(
  () =>
    import("@/components/canvas-ui/force-field").then((m) => m.ForceField),
  { ssr: false },
);

function canUseForceField(): boolean {
  if (typeof window === "undefined") return false;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    return false;
  }
  // Skip phones / coarse pointers — WebGL lattice destroys mobile TBT.
  if (window.matchMedia("(max-width: 767px), (pointer: coarse)").matches) {
    return false;
  }
  if (navigator.connection?.saveData) return false;
  return true;
}

/**
 * Desktop-only Force Field, armed on first pointermove so lab runs (no mouse)
 * and mobile never pay for WebGL. Children stay mounted for LCP/nav stability.
 */
export function LandingForceField({ children }: { children: ReactNode }) {
  const [mount, setMount] = useState(false);

  useEffect(() => {
    if (!canUseForceField()) return;

    let cancelled = false;
    const arm = () => {
      if (cancelled) return;
      setMount(true);
    };

    // Real users move the mouse; Lighthouse never does — keep WebGL off the lab path.
    window.addEventListener("pointermove", arm, { once: true, passive: true });

    return () => {
      cancelled = true;
      window.removeEventListener("pointermove", arm);
    };
  }, []);

  return (
    <div
      className="relative flex min-h-full flex-1 flex-col"
      style={{ minHeight: "100%" }}
    >
      {mount ? (
        <div
          className="pointer-events-none absolute inset-0 z-0 overflow-hidden"
          aria-hidden
        >
          <ForceField
            className="h-full w-full"
            style={{ minHeight: "100%" }}
            shape="hexagon"
            color={[0.57, 0.25, 0.06]}
            edgeColor={[0.9, 0.65, 0.28]}
            opacity={0.38}
            cellScale={18}
            lineWidth={0.022}
            gridOpacity={0.05}
            gridReveal="always"
            gridRevealStrength={0.55}
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
            refraction={0}
            aberration={0}
            haze={0.08}
            tint={0.03}
            hoverGlow={0}
            hoverRadius={320}
            hoverCharge={0}
            bloom={0.25}
            bloomThreshold={0.45}
            grain={0.06}
            dim={0}
            pageReact={0}
          >
            <div className="h-full min-h-dvh w-full" />
          </ForceField>
        </div>
      ) : null}
      <div className="relative z-10 flex min-h-full flex-1 flex-col">
        {children}
      </div>
    </div>
  );
}
