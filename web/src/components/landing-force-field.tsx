"use client";

import dynamic from "next/dynamic";
import { useEffect, useState, type ReactNode } from "react";

const ForceField = dynamic(
  () =>
    import("@/components/canvas-ui/force-field").then((m) => m.ForceField),
  { ssr: false },
);

/**
 * Muted Force Field as a deferred overlay — children stay mounted so LCP/nav
 * are not reset when WebGL loads after idle.
 */
export function LandingForceField({ children }: { children: ReactNode }) {
  const [mount, setMount] = useState(false);

  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      return;
    }

    let cancelled = false;
    const enable = () => {
      if (!cancelled) setMount(true);
    };

    const ric = window.requestIdleCallback?.(enable, { timeout: 2500 });
    if (ric == null) {
      const t = window.setTimeout(enable, 1200);
      return () => {
        cancelled = true;
        window.clearTimeout(t);
      };
    }

    return () => {
      cancelled = true;
      window.cancelIdleCallback?.(ric);
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
