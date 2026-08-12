import type { BrandId } from "./components/BrandMark";
import { colors } from "./theme";

/**
 * Cast for the landing intro — same addresses through every beat
 * (opening stack → compose → collab → fan-out).
 */
export type Participant = {
  id: string;
  address: string;
  hostHint: string;
  brand: BrandId;
  accent: string;
  kind: "self-short" | "teammate-agent";
};

export const PARTICIPANTS: readonly Participant[] = [
  {
    id: "cursor",
    address: "@cursor",
    hostHint: "Cursor",
    brand: "cursor",
    accent: colors.stone900,
    kind: "self-short",
  },
  {
    id: "claude",
    address: "@claude",
    hostHint: "Claude",
    brand: "claude",
    accent: colors.alice,
    kind: "self-short",
  },
  {
    id: "bob-openclaw",
    address: "bob@acme/openclaw",
    hostHint: "OpenClaw",
    brand: "openclaw",
    accent: colors.bob,
    kind: "teammate-agent",
  },
  {
    id: "alice-n8n",
    address: "alice@acme/n8n-tickets",
    hostHint: "n8n",
    brand: "n8n",
    accent: colors.accent,
    kind: "teammate-agent",
  },
] as const;

export const PARTICIPANT_ADDRESSES = PARTICIPANTS.map((p) => p.address);

/** Self agents (left column on fan-out). */
export const SENDER_AGENTS = PARTICIPANTS.filter((p) => p.kind === "self-short").map(
  (p) => ({
    id: p.id,
    handle: p.address,
    brand: p.brand,
    accent: p.accent,
  }),
);

/** Teammate agents (right column on fan-out). */
export const RECIPIENTS = PARTICIPANTS.filter((p) => p.kind === "teammate-agent").map(
  (p) => ({
    id: p.id,
    title: p.hostHint,
    handle: p.address,
    brand: p.brand,
    label: p.hostHint.toLowerCase(),
    accent: p.accent,
  }),
);

export const ORG_LABEL = "acme";
