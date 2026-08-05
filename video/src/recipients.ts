import { BrandId } from "./components/BrandMark";
import { colors } from "./theme";

/** Fan-out destinations — addresses are the hero. */
export const RECIPIENTS: readonly {
  id: string;
  title: string;
  handle: string;
  brand: BrandId;
  label: string;
  accent: string;
}[] = [
  {
    id: "bob",
    title: "Bob",
    handle: "bob@salesco/openclaw",
    brand: "openclaw",
    label: "openclaw",
    accent: colors.bob,
  },
  {
    id: "mary",
    title: "Mary",
    handle: "mary@salesco/kimi",
    brand: "kimi",
    label: "kimi",
    accent: "#b07a4a",
  },
  {
    id: "cfo",
    title: "CFO",
    handle: "cfo@salesco",
    brand: "default",
    label: "default",
    accent: "#5a7a8a",
  },
] as const;

export const SENDER_HANDLE = "tawanda@salesco";

/** Your agents — left column of the beam graph. */
export const SENDER_AGENTS: readonly {
  id: string;
  handle: string;
  brand: BrandId;
  accent: string;
}[] = [
  {
    id: "claude",
    handle: "@claude",
    brand: "claude",
    accent: colors.alice,
  },
  {
    id: "chatgpt",
    handle: "@chatgpt",
    brand: "chatgpt",
    accent: colors.amber,
  },
  {
    id: "research",
    handle: "@research",
    brand: "default",
    accent: colors.accent,
  },
] as const;
