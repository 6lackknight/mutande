"use client";

import { useEffect, type ReactNode } from "react";
import { initMixpanel } from "@/lib/mixpanel";

function scheduleMixpanelInit(): () => void {
  let cancelled = false;
  let ricId: number | undefined;
  let timeoutId: number | undefined;

  const start = () => {
    if (!cancelled) initMixpanel();
  };

  const afterLoad = () => {
    if (typeof window.requestIdleCallback === "function") {
      ricId = window.requestIdleCallback(start, { timeout: 4000 });
    } else {
      timeoutId = window.setTimeout(start, 1500);
    }
  };

  if (document.readyState === "complete") {
    afterLoad();
  } else {
    window.addEventListener("load", afterLoad, { once: true });
  }

  return () => {
    cancelled = true;
    window.removeEventListener("load", afterLoad);
    if (ricId != null) window.cancelIdleCallback?.(ricId);
    if (timeoutId != null) window.clearTimeout(timeoutId);
  };
}

/** Defers Mixpanel until after window load + idle so it stays off the critical path. */
export function MixpanelProvider({ children }: { children: ReactNode }) {
  useEffect(() => scheduleMixpanelInit(), []);

  return <>{children}</>;
}
