"use client";

import { useEffect, type ReactNode } from "react";
import { initMixpanel } from "@/lib/mixpanel";

export function MixpanelProvider({ children }: { children: ReactNode }) {
  useEffect(() => {
    initMixpanel();
  }, []);

  return <>{children}</>;
}
