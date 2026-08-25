/** PROTOTYPE — throwaway mock mail. Wipe with the route. */

export type ThreadStatus = "needsYou" | "open" | "closed";
export type ThreadFilter = "all" | "needs_action" | "open" | "closed" | "collab" | "unfiled";

export type ProtoThread = {
  id: string;
  title: string;
  from: string;
  snippet: string;
  status: ThreadStatus;
  filed: "collab" | "unfiled" | null;
  time: string;
};

export type ProtoAddress = {
  id: string;
  label: string;
  hint: string;
};

export const FILTERS: { id: ThreadFilter; label: string }[] = [
  { id: "all", label: "All" },
  { id: "needs_action", label: "Needs you" },
  { id: "open", label: "Open" },
  { id: "closed", label: "Closed" },
  { id: "collab", label: "Collab" },
  { id: "unfiled", label: "Unfiled" },
];

export const ADDRESSES: ProtoAddress[] = [
  { id: "@all", label: "@all", hint: "your agents" },
  { id: "@claude", label: "@claude", hint: "claude" },
  { id: "@chatgpt", label: "@chatgpt", hint: "chatgpt" },
  { id: "alice@acme", label: "alice@acme", hint: "teammate" },
  { id: "alice@acme/claude", label: "alice@acme/claude", hint: "her claude" },
];

export const INITIAL_THREADS: ProtoThread[] = [
  {
    id: "t1",
    title: "Q3 plan critique",
    from: "@claude",
    snippet: "Draft ready. Want another intelligence to review?",
    status: "needsYou",
    filed: null,
    time: "4m",
  },
  {
    id: "t2",
    title: "Ping @all",
    from: "@chatgpt",
    snippet: "Pong — caught up.",
    status: "open",
    filed: null,
    time: "1h",
  },
  {
    id: "t3",
    title: "Blob handoff",
    from: "alice@acme",
    snippet: "cut_v3.mp4 · nested replies",
    status: "open",
    filed: "unfiled",
    time: "1d",
  },
  {
    id: "t4",
    title: "Safety numbers",
    from: "@claude",
    snippet: "Verified this device.",
    status: "closed",
    filed: "collab",
    time: "1w",
  },
];

export function filterThreads(threads: ProtoThread[], filter: ThreadFilter) {
  switch (filter) {
    case "needs_action":
      return threads.filter((t) => t.status === "needsYou");
    case "open":
      return threads.filter((t) => t.status !== "closed");
    case "closed":
      return threads.filter((t) => t.status === "closed");
    case "collab":
      return threads.filter((t) => t.filed === "collab");
    case "unfiled":
      return threads.filter((t) => t.filed === "unfiled");
    default:
      return threads;
  }
}

export function matchAddresses(query: string): ProtoAddress[] {
  const q = query.trim().toLowerCase();
  if (!q) return ADDRESSES;
  return ADDRESSES.filter(
    (a) => a.label.startsWith(q) || a.label.includes(q),
  );
}
