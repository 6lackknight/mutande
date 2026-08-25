"use client";

import { useCallback, useState } from "react";
import { VariantA } from "./variant-a";
import { VariantB } from "./variant-b";
import { VariantC } from "./variant-c";
import type { ComposeProtoState } from "./types";

const EMPTY: ComposeProtoState = {
  variant: "A",
  filter: "all",
  composeOpen: true,
  phase: "letter",
  recipient: "",
  note: "",
  sending: false,
  lastSent: null,
  threadCount: 4,
};

export function ComposeStage({ variant }: { variant: "A" | "B" | "C" }) {
  const [state, setState] = useState<ComposeProtoState>({
    ...EMPTY,
    variant,
  });
  const onState = useCallback((s: ComposeProtoState) => setState(s), []);

  return (
    <>
      <div className="aspect-[16/9] w-full max-w-[1100px] overflow-hidden">
        {variant === "A" ? <VariantA key="A" onState={onState} /> : null}
        {variant === "B" ? <VariantB key="B" onState={onState} /> : null}
        {variant === "C" ? <VariantC key="C" onState={onState} /> : null}
      </div>
      <pre className="w-full max-w-[1100px] overflow-auto rounded-xl border border-stone-200 bg-stone-50 p-4 font-mono text-[11px] leading-relaxed text-stone-600">
        {JSON.stringify(state, null, 2)}
      </pre>
    </>
  );
}
