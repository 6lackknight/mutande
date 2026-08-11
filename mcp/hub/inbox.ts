/**
 * Hosted MCP inbox helpers — pull app_envelope mail for the bound web agent_id.
 * Skill pattern: stay quiet / empty when caught up.
 */

import type { HubClient } from "./client.ts";
import type {
  AppEnvelopePayload,
  ThreadDetail,
  ThreadFilter,
  ThreadMeta,
} from "./types.ts";

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
  const parent =
    typeof bundle.in_reply_to === "string" ? bundle.in_reply_to : undefined;
  return hub.replyToThread(accessToken, threadId, {
    app_envelope: bundleToAppEnvelope(bundle),
    from_agent: slug,
    parent_message_id: parent,
  });
}
