/**
 * Hosted MCP inbox helpers — pull app_envelope mail for the bound web agent_id.
 * Skill pattern: stay quiet / empty when caught up.
 */

import type { HubClient, HubClientError } from "./client.ts";
import { prepareBundleResources } from "./resources.ts";
import type {
  AgentsListResponse,
  AppEnvelopePayload,
  Contact,
  CreateThreadResponse,
  ThreadDetail,
  ThreadFilter,
  ThreadMeta,
  ToggleUpvoteResponse,
} from "./types.ts";

export { HOST_PATH_REFUSAL, prepareBundleResources } from "./resources.ts";

/** Clear refusal when hub would require E2E seal (sidecar-only path). */
export const E2E_REFUSAL =
  "Hosted MCP can only start app_envelope threads (never E2E). This recipient resolves to an E2E path — use the mutande Mac sidecar MCP for E2E mail, or address a web (mcp) agent.";

/** Thread is relevant to this web agent slot. */
export function threadForWebAgent(thread: ThreadMeta, agentId: string): boolean {
  const mode = thread.encryption_mode ?? "e2e";
  if (mode !== "app_envelope") return false;

  if (thread.audience_agent_id === agentId || thread.from_agent_id === agentId) {
    return true;
  }

  // Personal my-agents group (@all) — shared among the user's agents.
  if (thread.kind === "broadcast" && thread.audience === "@all") {
    return true;
  }

  return false;
}

export function filterThreadsForWebAgent(
  threads: ThreadMeta[],
  agentId: string,
): ThreadMeta[] {
  return threads.filter((t) => threadForWebAgent(t, agentId));
}

/** Concise agent/handle label for list rows (e.g. `cursor`, `chatgpt`, `@all`). */
export function participantLabel(addr: string): string {
  const trimmed = addr.trim();
  if (!trimmed) return "";
  const lower = trimmed.toLowerCase();
  if (lower === "@all" || lower.startsWith("@all@")) return lower;
  if (lower.startsWith("@") && !lower.includes("/")) {
    return lower.slice(1) || lower;
  }
  const slash = trimmed.lastIndexOf("/");
  if (slash >= 0) {
    const slug = trimmed.slice(slash + 1).trim().toLowerCase();
    if (slug && slug !== "default") return slug;
    return trimmed.slice(0, slash).trim().toLowerCase();
  }
  return lower;
}

function truncatePreview(s: string, maxChars: number): string {
  const collapsed = s.split(/\s+/).filter(Boolean).join(" ");
  if (collapsed.length <= maxChars) return collapsed;
  return `${collapsed.slice(0, Math.max(0, maxChars - 1)).trimEnd()}…`;
}

function bundleSubject(
  envelope: { subject?: string } | undefined | null,
): string | undefined {
  const s = envelope?.subject?.trim();
  return s ? s : undefined;
}

/** Body peek — notes, then question/answer prompts (Mac list preview). */
function bundleNotesPeek(
  envelope: {
    notes?: string;
    questions?: unknown[];
    answers?: unknown[];
    resource_requests?: unknown[];
  } | undefined | null,
): string | undefined {
  if (!envelope) return undefined;
  const notes = envelope.notes?.trim();
  if (notes) return notes;
  for (const q of envelope.questions ?? []) {
    if (q && typeof q === "object" && "prompt" in q) {
      const p = String((q as { prompt?: unknown }).prompt ?? "").trim();
      if (p) return p;
    }
  }
  for (const a of envelope.answers ?? []) {
    if (a && typeof a === "object" && "answer" in a) {
      const ans = String((a as { answer?: unknown }).answer ?? "").trim();
      if (ans) return ans;
    }
  }
  for (const r of envelope.resource_requests ?? []) {
    if (r && typeof r === "object") {
      const row = r as { description?: unknown; id?: unknown };
      const d = String(row.description ?? row.id ?? "").trim();
      if (d) return `Resource: ${d}`;
    }
  }
  return undefined;
}

/**
 * Fill last_from / last_subject / last_preview from app_envelope messages
 * (same precedence as Mac daemon after open).
 */
export function applyAppEnvelopeSnippets(
  thread: ThreadMeta,
  detail: ThreadDetail,
): ThreadMeta {
  const messages = detail.messages;
  if (messages.length === 0) return thread;

  const latest = messages.reduce((a, b) =>
    a.created_at >= b.created_at ? a : b
  );
  const roots = messages.filter((m) => !m.parent_message_id);
  const op = roots.length > 0
    ? roots.reduce((a, b) => (a.created_at <= b.created_at ? a : b))
    : messages.reduce((a, b) => (a.created_at <= b.created_at ? a : b));

  const subject = bundleSubject(latest.app_envelope) ??
    bundleSubject(op.app_envelope);
  const preview = bundleNotesPeek(latest.app_envelope);

  return {
    ...thread,
    last_from: latest.from_handle || thread.last_from,
    last_subject: subject
      ? truncatePreview(subject, 72)
      : thread.last_subject,
    last_preview: preview
      ? truncatePreview(preview, 96)
      : thread.last_preview,
  };
}

/** Display title — subject, else Mac-style address fallback. */
export function threadListTitle(thread: ThreadMeta): string {
  const subject = thread.last_subject?.trim();
  if (subject) return subject;
  const audience = thread.audience.trim();
  if (audience === "@all") return "@all";
  const fromBare = thread.from.split("/")[0]?.trim() ?? "";
  const audBare = audience.split("/")[0]?.trim() ?? "";
  if (
    fromBare &&
    audBare &&
    fromBare.toLowerCase() === audBare.toLowerCase() &&
    thread.from.trim().toLowerCase() !== audience.toLowerCase()
  ) {
    return audience;
  }
  return thread.from.trim() || audience || thread.id;
}

/** Ordered unique participant labels (from → to), concise for models. */
export function threadParticipants(thread: ThreadMeta): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const raw of [thread.from, thread.audience, thread.last_from]) {
    if (!raw?.trim()) continue;
    const label = participantLabel(raw);
    if (!label || seen.has(label)) continue;
    seen.add(label);
    out.push(label);
  }
  return out;
}

/**
 * Agent-facing list row: keep hub fields, add clear title/participants aliases.
 */
export function presentThreadListItem(thread: ThreadMeta): ThreadMeta & {
  thread_id: string;
  title: string;
  subject?: string;
  to: string;
  participants: string[];
  preview?: string;
} {
  const title = threadListTitle(thread);
  const subject = thread.last_subject?.trim() || undefined;
  const preview = thread.last_preview?.trim() || undefined;
  return {
    ...thread,
    thread_id: thread.id,
    title,
    ...(subject ? { subject } : {}),
    to: thread.audience,
    participants: threadParticipants(thread),
    ...(preview ? { preview } : {}),
  };
}

/** Strip E2E envelopes from the agent-facing view. */
export function presentThreadForWeb(detail: ThreadDetail): ThreadDetail {
  return {
    thread: detail.thread,
    messages: detail.messages.map((m) => {
      const { envelope: _e, ...rest } = m;
      return rest;
    }),
  };
}

export function bundleToAppEnvelope(
  bundle: Record<string, unknown>,
): AppEnvelopePayload {
  const version =
    typeof bundle.version === "number" && bundle.version >= 1
      ? bundle.version
      : 1;
  return { ...bundle, version };
}

/** True when hub error indicates E2E wire required. */
export function isE2eWireError(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err);
  const lower = msg.toLowerCase();
  return (
    lower.includes("e2e threads require envelope") ||
    lower.includes("require envelope (not app_envelope)") ||
    lower.includes("downgrade_required") ||
    lower.includes("cannot join e2e")
  );
}

export function mapHubSendError(err: unknown): Error {
  if (isE2eWireError(err)) {
    return new Error(E2E_REFUSAL);
  }
  return err instanceof Error ? err : new Error(String(err));
}

async function enrichListSnippets(
  hub: HubClient,
  accessToken: string,
  agentId: string,
  thread: ThreadMeta,
): Promise<ThreadMeta> {
  if (thread.last_subject?.trim() || thread.last_preview?.trim()) {
    return thread;
  }
  if ((thread.encryption_mode ?? "e2e") !== "app_envelope") {
    return thread;
  }
  try {
    const detail = await hub.fetchAppMessages(accessToken, thread.id, agentId);
    return applyAppEnvelopeSnippets(thread, detail);
  } catch {
    // Soft-fail: still return address-based title/participants.
    return thread;
  }
}

export async function listWebAgentThreads(
  hub: HubClient,
  accessToken: string,
  agentId: string,
  filter?: ThreadFilter,
  collabId?: string,
): Promise<{
  threads: ReturnType<typeof presentThreadListItem>[];
  caught_up: boolean;
}> {
  // Default skill check: needs_action. Empty → stay quiet.
  const effective: ThreadFilter | undefined = filter ?? "needs_action";
  const { threads } = await hub.listThreads(accessToken, effective);
  let mine = filterThreadsForWebAgent(threads, agentId);
  if (collabId) {
    mine = mine.filter((t) => t.collab_id === collabId);
  }
  const withSnippets = await Promise.all(
    mine.map((t) => enrichListSnippets(hub, accessToken, agentId, t)),
  );
  return {
    threads: withSnippets.map(presentThreadListItem),
    caught_up: mine.length === 0,
  };
}

export async function getWebAgentThread(
  hub: HubClient,
  accessToken: string,
  agentId: string,
  threadId: string,
): Promise<ThreadDetail> {
  const detail = await hub.fetchAppMessages(accessToken, threadId, agentId);
  if (!threadForWebAgent(detail.thread, agentId)) {
    throw new Error(
      "Thread is not addressed to this web agent (or is E2E-only)",
    );
  }
  return presentThreadForWeb(detail);
}

export async function replyAsWebAgent(
  hub: HubClient,
  accessToken: string,
  agentId: string,
  slug: string,
  threadId: string,
  bundle: Record<string, unknown>,
): Promise<{ message_id: string }> {
  // Ensure the thread is an app_envelope thread this agent can see.
  await getWebAgentThread(hub, accessToken, agentId, threadId);
  const prepared = prepareBundleResources(bundle);
  const parent =
    typeof prepared.in_reply_to === "string" ? prepared.in_reply_to : undefined;
  try {
    return await hub.replyToThread(accessToken, threadId, {
      app_envelope: bundleToAppEnvelope(prepared),
      from_agent: slug,
      from_agent_id: agentId,
      parent_message_id: parent,
    });
  } catch (e) {
    throw mapHubSendError(e);
  }
}

export async function listAgentsForUser(
  hub: HubClient,
  accessToken: string,
  handle?: string,
): Promise<AgentsListResponse> {
  return hub.listAgents(accessToken, handle);
}

/**
 * Org contacts (desktop list_contacts) plus approved external (L3).
 * External fetch failures are non-fatal — return org list alone.
 */
export async function listContactsForUser(
  hub: HubClient,
  accessToken: string,
): Promise<{ contacts: Contact[]; external_contacts: Contact[] }> {
  const org = await hub.listContacts(accessToken);
  let external: Contact[] = [];
  try {
    const ext = await hub.listExternalContacts(accessToken);
    external = ext.contacts;
  } catch (e) {
    const status =
      e && typeof e === "object" && "status" in e
        ? Number((e as HubClientError).status)
        : undefined;
    // 404/501 → older hub without L3; other errors still surface org list.
    if (status !== undefined && status !== 404 && status !== 501) {
      // Keep org contacts; note empty external on hard failure.
      external = [];
    }
  }
  return { contacts: org.contacts, external_contacts: external };
}

/**
 * Start a new app_envelope thread (no local draft store).
 * Never sends E2E envelopes — refuses when hub resolves the path to E2E.
 * Passes bound `from_agent_id` so dual-slot slugs are not remapped to sidecar.
 */
export async function forwardDraftAsWebAgent(
  hub: HubClient,
  accessToken: string,
  agentId: string,
  slug: string,
  recipient: string,
  bundle: Record<string, unknown>,
  collabId?: string,
): Promise<CreateThreadResponse> {
  if ("envelope" in bundle && bundle.envelope != null) {
    throw new Error(E2E_REFUSAL);
  }
  const to = recipient.trim();
  if (!to) {
    throw new Error("recipient is required");
  }
  if (collabId) {
    const { collab } = await hub.getCollab(accessToken, collabId);
    if (collab.encryption_mode === "e2e") {
      throw new Error(
        "This collab is E2E — use the mutande Mac sidecar MCP to file cards.",
      );
    }
  }
  const prepared = prepareBundleResources(bundle);
  try {
    const result = await hub.createThread(accessToken, {
      to,
      app_envelope: bundleToAppEnvelope(prepared),
      from_agent: slug,
      from_agent_id: agentId,
      ...(collabId ? { collab_id: collabId } : {}),
    });
    const threadId = result?.thread?.id?.trim();
    const messageId = result?.message_id?.trim();
    if (!threadId || !messageId) {
      throw new Error(
        "Hub createThread returned no thread_id/message_id — send did not succeed",
      );
    }
    return result;
  } catch (e) {
    throw mapHubSendError(e);
  }
}

export async function closeThreadAsUser(
  hub: HubClient,
  accessToken: string,
  threadId: string,
): Promise<{ thread: ThreadMeta }> {
  return hub.closeThread(accessToken, threadId);
}

export async function deleteThreadAsUser(
  hub: HubClient,
  accessToken: string,
  threadId: string,
): Promise<{ ok: true }> {
  return hub.deleteThread(accessToken, threadId);
}

export async function upvoteMessageAsWebAgent(
  hub: HubClient,
  accessToken: string,
  agentId: string,
  slug: string,
  threadId: string,
  messageId: string,
): Promise<ToggleUpvoteResponse> {
  return hub.upvoteMessage(accessToken, threadId, messageId, {
    from_agent_id: agentId,
    from_agent: slug,
  });
}

/**
 * Local sidecar mark_processed is in-memory bookkeeping with no hub API.
 * Hosted MCP documents N/A; agents should use list_threads filter=needs_action.
 */
export function markProcessedHosted(threadId: string): {
  ok: true;
  thread_id: string;
  na: true;
  message: string;
} {
  return {
    ok: true,
    thread_id: threadId,
    na: true,
    message:
      "N/A on hosted MCP — mark_processed is local sidecar bookkeeping only. Use list_threads with filter=needs_action (and reply/close) instead.",
  };
}
