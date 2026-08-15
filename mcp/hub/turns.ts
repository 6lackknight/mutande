/** Derive next_turn and hub `turns` mirror for hosted MCP compose. */

export type TurnActor = "agent" | "human";
export type MessageIntent = "question" | "answer" | "handoff" | "status" | "fyi";

export interface TurnEntry {
  address: string;
  actor: TurnActor;
  reason?:
    | { kind: "question"; question_id: string }
    | { kind: "review" }
    | { kind: "handoff" };
}

export interface HubTurn {
  user_id: string;
  actor: TurnActor;
}

export function parseIntent(raw: unknown): MessageIntent | undefined {
  if (typeof raw !== "string") return undefined;
  const v = raw.trim().toLowerCase();
  if (
    v === "question" ||
    v === "answer" ||
    v === "handoff" ||
    v === "status" ||
    v === "fyi"
  ) {
    return v;
  }
  return undefined;
}

export function inferIntent(bundle: Record<string, unknown>): MessageIntent {
  const parsed = parseIntent(bundle.intent);
  if (parsed) return parsed;
  if (Array.isArray(bundle.answers) && bundle.answers.length > 0) return "answer";
  if (Array.isArray(bundle.questions) && bundle.questions.length > 0) {
    return "question";
  }
  if (bundle.task && typeof bundle.task === "object") return "handoff";
  return "handoff";
}

function stripAgent(addr: string): string {
  const a = addr.trim();
  const slash = a.lastIndexOf("/");
  if (slash > 0) return a.slice(0, slash);
  return a;
}

function isBareRecipient(recipient: string | undefined): boolean {
  if (!recipient) return true;
  const r = recipient.trim();
  if (r.includes("/")) return false;
  if (r.startsWith("@") && !r.slice(1).includes("@")) return false;
  return true;
}

function parseTurnEntry(raw: unknown): TurnEntry | null {
  if (!raw || typeof raw !== "object") return null;
  const o = raw as Record<string, unknown>;
  const address = typeof o.address === "string" ? o.address.trim() : "";
  const actor = o.actor === "human" || o.actor === "agent" ? o.actor : null;
  if (!address || !actor) return null;
  let reason: TurnEntry["reason"];
  if (o.reason && typeof o.reason === "object") {
    const r = o.reason as Record<string, unknown>;
    if (r.kind === "question" && typeof r.question_id === "string") {
      reason = { kind: "question", question_id: r.question_id };
    } else if (r.kind === "review") {
      reason = { kind: "review" };
    } else if (r.kind === "handoff") {
      reason = { kind: "handoff" };
    }
  }
  return { address, actor, reason };
}

export function parseNextTurn(raw: unknown): TurnEntry[] {
  if (!Array.isArray(raw)) return [];
  return raw.map(parseTurnEntry).filter((e): e is TurnEntry => e != null);
}

export function deriveNextTurn(
  intent: MessageIntent,
  bundle: Record<string, unknown>,
  prior: TurnEntry[],
  senderAddress: string,
  recipient?: string,
  myBare?: string,
): TurnEntry[] {
  if (intent === "status" || intent === "fyi") return [];
  if (intent === "answer") {
    return prior.filter((e) => !replierHolds(e.address, senderAddress));
  }
  if (intent === "handoff") {
    if (!recipient) return [];
    return [{
      address: recipient,
      actor: isBareRecipient(recipient) ? "human" : "agent",
      reason: { kind: "handoff" },
    }];
  }
  // question
  const questions = Array.isArray(bundle.questions) ? bundle.questions : [];
  const out: TurnEntry[] = [];
  for (const q of questions) {
    if (!q || typeof q !== "object") continue;
    const o = q as Record<string, unknown>;
    const id = typeof o.id === "string" ? o.id : "q";
    const kind = typeof o.kind === "string" ? o.kind : "question";
    if (kind === "confirm_forward" || kind === "verify_contact") {
      out.push({
        address: myBare || stripAgent(senderAddress),
        actor: "human",
        reason: { kind: "review" },
      });
      continue;
    }
    const addr = recipient
      ? (isBareRecipient(recipient) ? stripAgent(recipient) : recipient)
      : (myBare || stripAgent(senderAddress));
    out.push({
      address: addr,
      actor: isBareRecipient(recipient) ? "human" : "agent",
      reason: { kind: "question", question_id: id },
    });
  }
  if (out.length === 0 && recipient) {
    out.push({
      address: recipient,
      actor: isBareRecipient(recipient) ? "human" : "agent",
      reason: { kind: "question", question_id: "q" },
    });
  }
  return out;
}

function agentSuffix(addr: string): string | undefined {
  const slash = addr.lastIndexOf("/");
  if (slash > 0) return addr.slice(slash + 1).toLowerCase();
  return undefined;
}

function replierHolds(entryAddr: string, replier: string): boolean {
  const a = entryAddr.trim().toLowerCase();
  const r = replier.trim().toLowerCase();
  if (a === r) return true;
  const aBare = stripAgent(a).toLowerCase();
  const rBare = stripAgent(r).toLowerCase();
  if (!aBare.startsWith("@") && !rBare.startsWith("@") && aBare === rBare) {
    return true;
  }
  if (a.startsWith("@") && !a.slice(1).includes("@") && a !== "@all") {
    const slug = agentSuffix(r);
    if (slug && slug === a.slice(1)) return true;
  }
  return false;
}

export function mergeReply(
  prior: TurnEntry[],
  replierAddress: string,
  declared: TurnEntry[],
  answers: { question_id?: string }[],
): TurnEntry[] {
  const answerIds = new Set(
    answers.map((a) => a.question_id).filter((id): id is string => Boolean(id)),
  );
  const kept = prior.filter((e) => {
    if (!replierHolds(e.address, replierAddress)) return true;
    if (e.reason?.kind === "question") {
      return !answerIds.has(e.reason.question_id);
    }
    return false;
  });
  for (const entry of declared) {
    const dup = kept.some((k) =>
      k.address.trim().toLowerCase() === entry.address.trim().toLowerCase() &&
      k.actor === entry.actor
    );
    if (!dup) kept.push(entry);
  }
  return kept;
}

export function foldAwaiting(
  messages: Array<{ from_handle: string; app_envelope?: Record<string, unknown> }>,
): TurnEntry[] {
  let declared = false;
  let awaiting: TurnEntry[] = [];
  for (const msg of messages) {
    const env = msg.app_envelope;
    if (!env) continue;
    const next = parseNextTurn(env.next_turn);
    const hasIntent = parseIntent(env.intent) != null;
    if (next.length === 0 && !hasIntent) continue;
    declared = true;
    const answers = Array.isArray(env.answers)
      ? (env.answers as { question_id?: string }[])
      : [];
    awaiting = mergeReply(awaiting, msg.from_handle, next, answers);
  }
  return declared ? awaiting : [];
}

export function hubTurnsMirror(
  awaiting: TurnEntry[],
  resolveUserId: (bare: string) => string | undefined,
): HubTurn[] {
  const out: HubTurn[] = [];
  for (const e of awaiting) {
    const userId = resolveUserId(stripAgent(e.address));
    if (!userId) continue;
    const existing = out.find((h) => h.user_id === userId);
    if (existing) {
      if (e.actor === "human") existing.actor = "human";
      continue;
    }
    out.push({ user_id: userId, actor: e.actor });
  }
  return out;
}

export function stampBundleV2(bundle: Record<string, unknown>): Record<string, unknown> {
  const intent = inferIntent(bundle);
  const next = parseNextTurn(bundle.next_turn);
  const version = typeof bundle.version === "number" && bundle.version >= 2
    ? bundle.version
    : 2;
  return {
    ...bundle,
    version,
    intent,
    next_turn: next,
  };
}
