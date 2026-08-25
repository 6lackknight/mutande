/** PROTOTYPE — live state dumped beside the stage. */

export type ComposeProtoState = {
  variant: string;
  filter: string;
  composeOpen: boolean;
  phase: string;
  recipient: string;
  note: string;
  sending: boolean;
  lastSent: { recipient: string; note: string } | null;
  threadCount: number;
};

export const EASE_OUT = [0.25, 1, 0.5, 1] as const;
export const EASE_EXPO = [0.16, 1, 0.3, 1] as const;

export const VARIANT_META = [
  { key: "A", name: "Inline letter" },
  { key: "B", name: "Spotlight dispatch" },
  { key: "C", name: "Reading-pane letter" },
] as const;
