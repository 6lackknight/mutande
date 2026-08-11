/**
 * L5 thread downgrade consent (directory.prd §4.2 rules 3–5, §6.5, §7.3, §13).
 *
 * Propose adding a web (mcp) agent to an E2E thread → unanimous sidecar
 * participant Approve/Deny → one-way flip to app_envelope + system divider.
 * Pre-downgrade E2E history stays sealed for the web joiner.
 */

import {
  buildAppEnvelopeRecord,
  normalizeEncryptionMode,
  APP_ENVELOPE_RETENTION_MS,
} from "./app_envelope.ts";
import { HubError, forbidden, notFound } from "./errors.ts";
import {
  formatDisplayAddress,
  formatWirePath,
  isMyAgentsHandle,
  parseUserHandle,
  stripAgentSuffix,
} from "./address.ts";
import type {
  Agent,
  AuthContext,
  InboxEntry,
  ProposeThreadDowngradeInput,
  ThreadDowngradeProposal,
  ThreadMessage,
  ThreadMeta,
  User,
} from "./types.ts";

export type DowngradeKvCtx = {
  kv: Deno.Kv;
  getUser: (id: string) => Promise<User | null>;
  getUserByHandle: (handle: string) => Promise<User | null>;
  getAgent: (id: string) => Promise<Agent | null>;
  listAgentsForUser: (userId: string) => Promise<Agent[]>;
  resolveAgentForUser: (userId: string, slug?: string) => Promise<Agent>;
  lookupMcpAgent: (userId: string, slug: string) => Promise<Agent | null>;
  getInboxEntry: (userId: string, threadId: string) => Promise<InboxEntry | null>;
  normalizeThread: (t: ThreadMeta) => ThreadMeta;
  threadVisibleToOrg: (auth: AuthContext, t: ThreadMeta) => boolean;
  threadKey: (id: string) => Deno.KvKey;
  messageKey: (threadId: string, messageId: string) => Deno.KvKey;
  messagesPrefix: (threadId: string) => Deno.KvKey;
  inboxKey: (userId: string, threadId: string) => Deno.KvKey;
  appEnvelopeKey: (threadId: string, messageId: string) => Deno.KvKey;
};

function nowIso(): string {
  return new Date().toISOString();
}

export function downgradeProposalKey(id: string): Deno.KvKey {
  return ["downgrade_proposals", id];
}

export function threadDowngradeProposalKey(
  threadId: string,
  proposalId: string,
): Deno.KvKey {
  return ["thread_downgrade_proposals", threadId, proposalId];
}

export function threadDowngradeProposalsPrefix(threadId: string): Deno.KvKey {
  return ["thread_downgrade_proposals", threadId];
}

export function userDowngradeProposalKey(
  userId: string,
  proposalId: string,
): Deno.KvKey {
  return ["user_downgrade_proposals", userId, proposalId];
}

export function userDowngradeProposalsPrefix(userId: string): Deno.KvKey {
  return ["user_downgrade_proposals", userId];
}

function dividerNotes(slug: string): string {
  return `E2E ended here — @${slug} (web) added, approved by all`;
}

/** Prompt copy shown to sidecar participants (§6.5). */
export function downgradePromptCopy(slug: string): string {
  return `Adding @${slug} (web) ends E2E for this thread`;
}

async function loadThread(
  ctx: DowngradeKvCtx,
  auth: AuthContext,
  threadId: string,
): Promise<{ thread: ThreadMeta; inbox: InboxEntry }> {
  const inbox = await ctx.getInboxEntry(auth.userId, threadId);
  if (!inbox) throw forbidden("Not a thread participant");

  const threadRes = await ctx.kv.get<ThreadMeta>(ctx.threadKey(threadId));
  const thread = threadRes.value ? ctx.normalizeThread(threadRes.value) : null;
  if (!thread || !ctx.threadVisibleToOrg(auth, thread)) throw notFound("Thread");
  return { thread, inbox };
}

async function listThreadMessages(
  ctx: DowngradeKvCtx,
  threadId: string,
): Promise<ThreadMessage[]> {
  const messages: ThreadMessage[] = [];
  const iter = ctx.kv.list<ThreadMessage>({ prefix: ctx.messagesPrefix(threadId) });
  for await (const entry of iter) {
    if (entry.value) messages.push(entry.value);
  }
  return messages;
}

/**
 * Sidecar agent_ids that must consent to downgrade.
 * Includes from/audience agents, message authors, and for @all all of the
 * owner's current sidecar slots.
 */
export async function collectSidecarApproverAgentIds(
  ctx: DowngradeKvCtx,
  thread: ThreadMeta,
): Promise<string[]> {
  const ids = new Set<string>();

  const consider = async (agentId: string | undefined) => {
    if (!agentId) return;
    const agent = await ctx.getAgent(agentId);
    if (agent?.transport === "sidecar") ids.add(agent.id);
  };

  await consider(thread.from_agent_id);
  await consider(thread.audience_agent_id);

  const messages = await listThreadMessages(ctx, thread.id);
  for (const msg of messages) {
    await consider(msg.from_agent_id);
  }

  if (isMyAgentsHandle(thread.audience)) {
    const agents = await ctx.listAgentsForUser(thread.from_user_id);
    for (const a of agents) {
      if (a.transport === "sidecar") ids.add(a.id);
    }
  }

  return [...ids].sort();
}

async function agentIdsForUser(
  ctx: DowngradeKvCtx,
  agentIds: string[],
  userId: string,
): Promise<string[]> {
  const out: string[] = [];
  for (const id of agentIds) {
    const agent = await ctx.getAgent(id);
    if (agent?.user_id === userId) out.push(id);
  }
  return out;
}

async function uniqueUserIdsForAgents(
  ctx: DowngradeKvCtx,
  agentIds: string[],
): Promise<string[]> {
  const users = new Set<string>();
  for (const id of agentIds) {
    const agent = await ctx.getAgent(id);
    if (agent) users.add(agent.user_id);
  }
  return [...users];
}

async function findPendingProposalForThread(
  ctx: DowngradeKvCtx,
  threadId: string,
): Promise<ThreadDowngradeProposal | null> {
  const iter = ctx.kv.list<string>({
    prefix: threadDowngradeProposalsPrefix(threadId),
  });
  for await (const entry of iter) {
    const id = entry.value;
    if (!id) continue;
    const res = await ctx.kv.get<ThreadDowngradeProposal>(downgradeProposalKey(id));
    if (res.value?.status === "pending") return res.value;
  }
  return null;
}

async function resolveProposedWebAgent(
  ctx: DowngradeKvCtx,
  auth: AuthContext,
  thread: ThreadMeta,
  agentSlug: string,
): Promise<Agent> {
  const slug = agentSlug.trim().toLowerCase().replace(/^@/, "");
  if (!slug) {
    throw new HubError("agent_slug is required", "invalid_argument", 400);
  }

  // Prefer caller's own mcp slot; else any thread participant's mcp slot.
  const candidates = new Set<string>([auth.userId, thread.from_user_id]);
  if (thread.participant_user_ids) {
    for (const uid of thread.participant_user_ids) candidates.add(uid);
  }
  // Teammate DM: audience handle names the other participant.
  if (thread.audience && !isMyAgentsHandle(thread.audience) &&
    !thread.audience.startsWith("@all@")) {
    const bare = stripAgentSuffix(thread.audience);
    const peer = await ctx.getUserByHandle(bare);
    if (peer) candidates.add(peer.id);
  }
  // Sidecar message authors / from+audience agents also count as participants.
  for (const agentId of [
    thread.from_agent_id,
    thread.audience_agent_id,
  ]) {
    if (!agentId) continue;
    const a = await ctx.getAgent(agentId);
    if (a) candidates.add(a.user_id);
  }

  for (const userId of candidates) {
    const agent = await ctx.lookupMcpAgent(userId, slug);
    if (!agent) continue;
    const inbox = await ctx.getInboxEntry(userId, thread.id);
    // Owner must already be on the thread (inbox), except self-collab proposer.
    if (userId === auth.userId || inbox) return agent;
  }

  throw new HubError(
    `No web agent '@${slug}' among thread participants`,
    "unknown_agent",
    400,
  );
}

export async function proposeThreadDowngrade(
  ctx: DowngradeKvCtx,
  auth: AuthContext,
  threadId: string,
  input: ProposeThreadDowngradeInput,
): Promise<{ proposal: ThreadDowngradeProposal; prompt: string }> {
  const { thread } = await loadThread(ctx, auth, threadId);

  if (thread.status === "closed") {
    throw new HubError("Thread is closed", "invalid_argument", 400);
  }

  const mode = normalizeEncryptionMode(thread.encryption_mode);
  if (mode !== "e2e") {
    throw new HubError(
      "Thread is already non-E2E — cannot re-upgrade or re-downgrade",
      "already_downgraded",
      409,
    );
  }
  if (thread.downgrade_point) {
    throw new HubError(
      "Thread already has a downgrade point — ratchet is one-way",
      "already_downgraded",
      409,
    );
  }

  const existing = await findPendingProposalForThread(ctx, threadId);
  if (existing) {
    throw new HubError(
      `A downgrade proposal is already pending (${existing.id})`,
      "downgrade_pending",
      409,
    );
  }

  const webAgent = await resolveProposedWebAgent(
    ctx,
    auth,
    thread,
    input.agent_slug,
  );
  if (webAgent.transport !== "mcp") {
    throw new HubError(
      "Only web (mcp) agents can trigger an E2E downgrade",
      "invalid_argument",
      400,
    );
  }

  const required = await collectSidecarApproverAgentIds(ctx, thread);
  if (required.length === 0) {
    throw new HubError(
      "No sidecar participants to approve this downgrade",
      "invalid_argument",
      400,
    );
  }

  let proposerAgent: Agent | undefined;
  if (input.from_agent?.trim()) {
    proposerAgent = await ctx.resolveAgentForUser(auth.userId, input.from_agent);
  }

  const ts = nowIso();
  const proposalId = crypto.randomUUID();

  // Proposer's sidecar agents on this thread auto-approve.
  const proposerApprovals = await agentIdsForUser(ctx, required, auth.userId);
  const approvals = [...proposerApprovals];

  let proposal: ThreadDowngradeProposal = {
    id: proposalId,
    thread_id: threadId,
    proposed_agent_id: webAgent.id,
    proposed_slug: webAgent.slug,
    proposer_user_id: auth.userId,
    ...(proposerAgent ? { proposer_agent_id: proposerAgent.id } : {}),
    status: "pending",
    required_approvers: required,
    approvals,
    denials: [],
    created_at: ts,
  };

  const approverUsers = await uniqueUserIdsForAgents(ctx, required);

  // Persist pending proposal first; may finalize immediately if unanimous.
  await persistProposal(ctx, proposal, approverUsers);

  if (isUnanimous(proposal)) {
    proposal = await finalizeApprovedDowngrade(ctx, auth, thread, proposal);
  }

  return {
    proposal,
    prompt: downgradePromptCopy(webAgent.slug),
  };
}

function isUnanimous(proposal: ThreadDowngradeProposal): boolean {
  const approved = new Set(proposal.approvals);
  return proposal.required_approvers.every((id) => approved.has(id));
}

async function persistProposal(
  ctx: DowngradeKvCtx,
  proposal: ThreadDowngradeProposal,
  approverUsers: string[],
): Promise<void> {
  const tx = ctx.kv.atomic();
  tx.set(downgradeProposalKey(proposal.id), proposal);
  tx.set(threadDowngradeProposalKey(proposal.thread_id, proposal.id), proposal.id);
  for (const userId of approverUsers) {
    tx.set(userDowngradeProposalKey(userId, proposal.id), proposal.id);
  }
  const res = await tx.commit();
  if (!res.ok) {
    throw new HubError("Failed to store downgrade proposal", "internal", 500);
  }
}

export async function approveThreadDowngrade(
  ctx: DowngradeKvCtx,
  auth: AuthContext,
  threadId: string,
  proposalId: string,
): Promise<{ proposal: ThreadDowngradeProposal; thread: ThreadMeta }> {
  const { thread } = await loadThread(ctx, auth, threadId);
  const proposal = await loadProposal(ctx, proposalId, threadId);

  if (proposal.status !== "pending") {
    throw new HubError("Proposal already resolved", "conflict", 409);
  }

  const mode = normalizeEncryptionMode(thread.encryption_mode);
  if (mode !== "e2e") {
    throw new HubError(
      "Thread is already non-E2E",
      "already_downgraded",
      409,
    );
  }

  const mine = await agentIdsForUser(ctx, proposal.required_approvers, auth.userId);
  if (mine.length === 0) {
    throw forbidden("Only sidecar participants can approve");
  }

  const approvals = new Set(proposal.approvals);
  for (const id of mine) approvals.add(id);

  let updated: ThreadDowngradeProposal = {
    ...proposal,
    approvals: [...approvals].sort(),
  };

  if (isUnanimous(updated)) {
    updated = await finalizeApprovedDowngrade(ctx, auth, thread, updated);
  } else {
    await ctx.kv.set(downgradeProposalKey(updated.id), updated);
  }

  const threadRes = await ctx.kv.get<ThreadMeta>(ctx.threadKey(threadId));
  const fresh = threadRes.value
    ? ctx.normalizeThread(threadRes.value)
    : thread;

  return { proposal: updated, thread: fresh };
}

export async function denyThreadDowngrade(
  ctx: DowngradeKvCtx,
  auth: AuthContext,
  threadId: string,
  proposalId: string,
): Promise<{ proposal: ThreadDowngradeProposal }> {
  const { thread } = await loadThread(ctx, auth, threadId);
  void thread;
  const proposal = await loadProposal(ctx, proposalId, threadId);

  if (proposal.status !== "pending") {
    throw new HubError("Proposal already resolved", "conflict", 409);
  }

  const mine = await agentIdsForUser(ctx, proposal.required_approvers, auth.userId);
  if (mine.length === 0) {
    // Proposer (non-approver edge) or any participant may deny to cancel.
    const inbox = await ctx.getInboxEntry(auth.userId, threadId);
    if (!inbox) throw forbidden("Not a thread participant");
  }

  const ts = nowIso();
  const denials = [...new Set([...proposal.denials, ...mine, auth.userId])];
  const updated: ThreadDowngradeProposal = {
    ...proposal,
    status: "denied",
    denials,
    resolved_at: ts,
  };
  await ctx.kv.set(downgradeProposalKey(updated.id), updated);
  return { proposal: updated };
}

async function loadProposal(
  ctx: DowngradeKvCtx,
  proposalId: string,
  threadId: string,
): Promise<ThreadDowngradeProposal> {
  const res = await ctx.kv.get<ThreadDowngradeProposal>(
    downgradeProposalKey(proposalId),
  );
  if (!res.value || res.value.thread_id !== threadId) {
    throw notFound("Downgrade proposal");
  }
  return res.value;
}

async function finalizeApprovedDowngrade(
  ctx: DowngradeKvCtx,
  auth: AuthContext,
  thread: ThreadMeta,
  proposal: ThreadDowngradeProposal,
): Promise<ThreadDowngradeProposal> {
  void auth;
  const webAgent = await ctx.getAgent(proposal.proposed_agent_id);
  if (!webAgent || webAgent.transport !== "mcp") {
    throw new HubError("Proposed web agent no longer available", "conflict", 409);
  }

  const owner = await ctx.getUser(webAgent.user_id);
  if (!owner?.handle) throw notFound("Web agent owner");
  const ownerParts = parseUserHandle(owner.handle);

  const ts = nowIso();
  const dividerId = crypto.randomUUID();
  const approvers = [...proposal.required_approvers].sort();

  const dividerPayload = {
    version: 1 as const,
    subject: "E2E ended",
    notes: dividerNotes(webAgent.slug),
    system_kind: "e2e_ended" as const,
  };
  const dividerRecord = await buildAppEnvelopeRecord({
    threadId: thread.id,
    messageId: dividerId,
    fromUserId: "system",
    createdAt: ts,
    payload: dividerPayload,
  });

  const dividerMessage: ThreadMessage = {
    id: dividerId,
    thread_id: thread.id,
    from_user_id: "system",
    from_handle: "mutande",
    content_store: "app_envelope",
    created_at: ts,
  };

  const updatedThread: ThreadMeta = {
    ...thread,
    encryption_mode: "app_envelope",
    downgrade_point: {
      message_id: dividerId,
      approvers,
    },
    audience: formatDisplayAddress(
      ownerParts.local,
      ownerParts.orgSlug,
      webAgent.slug,
    ),
    audience_agent_id: webAgent.id,
    audience_wire_path: formatWirePath(
      ownerParts.orgSlug,
      ownerParts.local,
      webAgent.slug,
    ),
    reply_count: thread.reply_count + 1,
    updated_at: ts,
  };

  const resolved: ThreadDowngradeProposal = {
    ...proposal,
    status: "approved",
    approvals: approvers,
    resolved_at: ts,
    divider_message_id: dividerId,
  };

  // Ensure web agent owner has inbox (usually already does as participant).
  const ownerInbox = await ctx.getInboxEntry(webAgent.user_id, thread.id);
  const inboxEntry: InboxEntry = ownerInbox ?? {
    thread_id: thread.id,
    your_status: "pending",
    role: webAgent.user_id === thread.from_user_id ? "sender" : "recipient",
    updated_at: ts,
  };

  for (let attempt = 0; attempt < 8; attempt++) {
    const tx = ctx.kv.atomic();
    tx.set(ctx.threadKey(thread.id), updatedThread);
    tx.set(ctx.messageKey(thread.id, dividerId), dividerMessage);
    tx.set(ctx.appEnvelopeKey(thread.id, dividerId), dividerRecord, {
      expireIn: APP_ENVELOPE_RETENTION_MS,
    });
    tx.set(downgradeProposalKey(resolved.id), resolved);
    tx.set(ctx.inboxKey(webAgent.user_id, thread.id), {
      ...inboxEntry,
      updated_at: ts,
    });
    const res = await tx.commit();
    if (res.ok) return resolved;
  }
  throw new HubError("Failed to finalize thread downgrade", "internal", 500);
}

export async function listPendingThreadDowngrades(
  ctx: DowngradeKvCtx,
  auth: AuthContext,
): Promise<{ proposals: ThreadDowngradeProposal[] }> {
  const proposals: ThreadDowngradeProposal[] = [];
  const iter = ctx.kv.list<string>({
    prefix: userDowngradeProposalsPrefix(auth.userId),
  });
  for await (const entry of iter) {
    const id = entry.value;
    if (!id) continue;
    const res = await ctx.kv.get<ThreadDowngradeProposal>(downgradeProposalKey(id));
    if (res.value?.status === "pending") {
      proposals.push(res.value);
    }
  }
  proposals.sort((a, b) => b.created_at.localeCompare(a.created_at));
  return { proposals };
}

export async function getPendingThreadDowngrade(
  ctx: DowngradeKvCtx,
  auth: AuthContext,
  threadId: string,
): Promise<ThreadDowngradeProposal | null> {
  const inbox = await ctx.getInboxEntry(auth.userId, threadId);
  if (!inbox) return null;
  return findPendingProposalForThread(ctx, threadId);
}

/**
 * Whether a message is visible to a web joiner after downgrade.
 * Pre-downgrade E2E history stays sealed (§4.2 rule 4).
 */
export function messageVisibleAfterDowngrade(
  thread: ThreadMeta,
  msg: ThreadMessage,
): boolean {
  const point = thread.downgrade_point;
  if (!point) {
    // No downgrade — app_envelope-from-birth threads show all app messages.
    return (msg.content_store ?? "e2e") === "app_envelope" || !msg.envelope;
  }
  if (msg.id === point.message_id) return true;
  if ((msg.content_store ?? "e2e") === "app_envelope") return true;
  // E2E messages before the join point stay sealed.
  return false;
}
