import { BrandId } from "./components/BrandMark";
import { colors } from "./theme";

/** Fan-out destinations (wrap-to-N). */
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

export const SENDER_HANDLE = "alice@salesco";
