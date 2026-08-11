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

export async function listWebAgentThreads(
  hub: HubClient,
  accessToken: string,
  agentId: string,
  filter?: ThreadFilter,
): Promise<{ threads: ThreadMeta[]; caught_up: boolean }> {
  // Default skill check: needs_action. Empty → stay quiet.
  const effective: ThreadFilter | undefined = filter ?? "needs_action";
  const { threads } = await hub.listThreads(accessToken, effective);
  const mine = filterThreadsForWebAgent(threads, agentId);
  return { threads: mine, caught_up: mine.length === 0 };
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
): Promise<CreateThreadResponse> {
  if ("envelope" in bundle && bundle.envelope != null) {
    throw new Error(E2E_REFUSAL);
  }
  const to = recipient.trim();
  if (!to) {
    throw new Error("recipient is required");
  }
  const prepared = prepareBundleResources(bundle);
  try {
    const result = await hub.createThread(accessToken, {
      to,
      app_envelope: bundleToAppEnvelope(prepared),
      from_agent: slug,
      from_agent_id: agentId,
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
