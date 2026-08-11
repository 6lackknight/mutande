/**
 * HubStore pairing / external-contact methods (directory.prd §6.2–6.6).
 * Kept separate so store.ts stays readable; HubStore mixes these in via Object.assign
 * pattern is awkward in TS — instead we export free functions that take a store ctx.
 */

import { forbidden, HubError, notFound } from "./errors.ts";
import {
  buildAppEnvelopeRecord,
} from "./app_envelope.ts";
import type {
  AuthContext,
  Contact,
  DevicePlatform,
  ExternalContactLink,
  PairRequest,
  PairingOpsFlag,
  PairingPin,
  PairingPinResponse,
  SubmitPairRequestInput,
  ThreadMessage,
  ThreadMeta,
  User,
} from "./types.ts";
import {
  assertUnderDailyCap,
  buildPairingQrUri,
  clearPairFailures,
  externalLinkByUserKey,
  externalLinkKey,
  externalLinkMsgCountKey,
  externalLinkPairKey,
  externalLinksByUserPrefix,
  generateSixDigitPin,
  isPairLocked,
  issuePairingPinRecord,
  pairBlockKey,
  pairDenyKey,
  pairDeniesPrefix,
  pairFailureKey,
  pairRequestByRequesterKey,
  pairRequestByTargetKey,
  pairRequestKey,
  pairRequestsByRequesterPrefix,
  pairRequestsByTargetPrefix,
  pairSubmitRequesterKey,
  pairSubmitTargetKey,
  pairingFailed,
  pairingOpsFlagKey,
  pairingOpsFlagsPrefix,
  pairingPinKey,
  pairingRateLimited,
  pinIsValid,
  recordWrongPin,
  toPairingPinResponse,
  utcDay,
  EXTERNAL_LINK_MSGS_PER_DAY,
  PAIR_DENY_OPS_THRESHOLD,
  PAIR_DENY_OPS_WINDOW_MS,
  PAIR_SUBMISSIONS_PER_REQUESTER_DAY,
  PAIR_SUBMISSIONS_PER_TARGET_DAY,
  type PairFailureState,
} from "./external_pairing.ts";

export interface PairingKvCtx {
  kv: Deno.Kv;
  getUser(id: string): Promise<User | null>;
  getUserByHandle(handle: string): Promise<User | null>;
  listDevicesForUser(userId: string): Promise<
    Array<{ pubkey: string; platform: DevicePlatform }>
  >;
  inboxKey(userId: string, threadId: string): Deno.KvKey;
  threadKey(id: string): Deno.KvKey;
  messageKey(threadId: string, messageId: string): Deno.KvKey;
}

function nowIso(): string {
  return new Date().toISOString();
}

function normalizeHandle(handle: string): string {
  return handle.trim().toLowerCase();
}

export async function issuePairingPin(
  ctx: PairingKvCtx,
  auth: AuthContext,
): Promise<PairingPinResponse> {
  const user = await ctx.getUser(auth.userId);
  if (!user?.handle) throw notFound("User");
  const record = issuePairingPinRecord(auth.userId, user.handle);
  await ctx.kv.set(pairingPinKey(auth.userId), record);
  return toPairingPinResponse(record);
}

export async function getPairingPin(
  ctx: PairingKvCtx,
  auth: AuthContext,
): Promise<PairingPinResponse | null> {
  const res = await ctx.kv.get<PairingPin>(pairingPinKey(auth.userId));
  if (!pinIsValid(res.value)) return null;
  return toPairingPinResponse(res.value!);
}

export async function rotatePairingPin(
  ctx: PairingKvCtx,
  auth: AuthContext,
): Promise<PairingPinResponse> {
  return issuePairingPin(ctx, auth);
}

export async function findExternalLinkBetween(
  ctx: PairingKvCtx,
  userA: string,
  userB: string,
): Promise<ExternalContactLink | null> {
  const pairRes = await ctx.kv.get<string>(externalLinkPairKey(userA, userB));
  if (!pairRes.value) return null;
  const linkRes = await ctx.kv.get<ExternalContactLink>(
    externalLinkKey(pairRes.value),
  );
  return linkRes.value;
}

export async function hasApprovedExternalContact(
  ctx: PairingKvCtx,
  userId: string,
  otherHandle: string,
): Promise<ExternalContactLink | null> {
  const other = await ctx.getUserByHandle(normalizeHandle(otherHandle));
  if (!other) return null;
  return findExternalLinkBetween(ctx, userId, other.id);
}

export async function listExternalContacts(
  ctx: PairingKvCtx,
  auth: AuthContext,
): Promise<{ contacts: Contact[] }> {
  const contacts: Contact[] = [];
  const iter = ctx.kv.list<string>({
    prefix: externalLinksByUserPrefix(auth.userId),
  });
  for await (const entry of iter) {
    const linkRes = await ctx.kv.get<ExternalContactLink>(
      externalLinkKey(entry.value),
    );
    const link = linkRes.value;
    if (!link) continue;
    const otherId =
      link.user_a_id === auth.userId ? link.user_b_id : link.user_a_id;
    const otherHandle =
      link.user_a_id === auth.userId ? link.user_b_handle : link.user_a_handle;
    const devices = await ctx.listDevicesForUser(otherId);
    contacts.push({
      handle: otherHandle,
      pubkey: devices[0]?.pubkey ?? null,
      devices,
      kind: "external",
      external_link_id: link.id,
      linked_at: link.created_at,
      thread_id: link.thread_id,
    });
  }
  contacts.sort((a, b) => a.handle.localeCompare(b.handle));
  return { contacts };
}

export async function submitPairRequest(
  ctx: PairingKvCtx,
  auth: AuthContext,
  input: SubmitPairRequestInput,
): Promise<{ request: PairRequest }> {
  const targetHandle = normalizeHandle(input.handle);
  const pin = (input.pin ?? "").trim();
  if (!/^\d{6}$/.test(pin)) throw pairingFailed();
  if (!targetHandle.includes("@")) throw pairingFailed();

  const me = await ctx.getUser(auth.userId);
  if (!me?.handle) throw notFound("User");
  if (normalizeHandle(me.handle) === targetHandle) {
    throw new HubError("Cannot pair with yourself", "invalid_argument", 400);
  }

  // Same-org: no PIN pairing (already contacts).
  const target = await ctx.getUserByHandle(targetHandle);
  if (target?.org_id && target.org_id === auth.orgId) {
    throw new HubError(
      "That handle is already in your org",
      "invalid_argument",
      400,
    );
  }

  // Block list (target blocked requester) — uniform error.
  if (target) {
    const block = await ctx.kv.get(
      pairBlockKey(target.id, normalizeHandle(me.handle)),
    );
    if (block.value) throw pairingFailed();
  }

  // Existing link?
  if (target) {
    const existing = await findExternalLinkBetween(ctx, auth.userId, target.id);
    if (existing) {
      throw new HubError("Already connected", "conflict", 409);
    }
  }

  // Per-pair lockout (even if handle unknown — keyed by handle string).
  const failRes = await ctx.kv.get<PairFailureState>(
    pairFailureKey(auth.userId, targetHandle),
  );
  if (isPairLocked(failRes.value)) throw pairingRateLimited();

  const day = utcDay();
  const reqCountRes = await ctx.kv.get<number>(
    pairSubmitRequesterKey(auth.userId, day),
  );
  assertUnderDailyCap(reqCountRes.value ?? 0, PAIR_SUBMISSIONS_PER_REQUESTER_DAY);
  const tgtCountRes = await ctx.kv.get<number>(
    pairSubmitTargetKey(targetHandle, day),
  );
  assertUnderDailyCap(tgtCountRes.value ?? 0, PAIR_SUBMISSIONS_PER_TARGET_DAY);

  // Increment submission counters before PIN check (counts as an attempt).
  await ctx.kv.set(
    pairSubmitRequesterKey(auth.userId, day),
    (reqCountRes.value ?? 0) + 1,
  );
  await ctx.kv.set(
    pairSubmitTargetKey(targetHandle, day),
    (tgtCountRes.value ?? 0) + 1,
  );

  // Uniform: unknown handle / wrong / expired PIN → same error.
  if (!target?.handle) {
    await ctx.kv.set(
      pairFailureKey(auth.userId, targetHandle),
      recordWrongPin(failRes.value),
    );
    throw pairingFailed();
  }

  const pinRes = await ctx.kv.get<PairingPin>(pairingPinKey(target.id));
  const theirPin = pinRes.value;
  if (!pinIsValid(theirPin) || theirPin!.pin !== pin) {
    await ctx.kv.set(
      pairFailureKey(auth.userId, targetHandle),
      recordWrongPin(failRes.value),
    );
    throw pairingFailed();
  }

  // Success — clear failures.
  await ctx.kv.set(
    pairFailureKey(auth.userId, targetHandle),
    clearPairFailures(),
  );

  // Pending duplicate?
  const existingPending = await findPendingBetween(
    ctx,
    auth.userId,
    target.id,
  );
  if (existingPending) {
    return { request: existingPending };
  }

  const intro = input.intro?.trim().slice(0, 500) || undefined;
  const request: PairRequest = {
    id: crypto.randomUUID(),
    requester_user_id: auth.userId,
    requester_handle: me.handle,
    target_user_id: target.id,
    target_handle: target.handle,
    ...(intro ? { intro } : {}),
    status: "pending",
    created_at: nowIso(),
  };

  const tx = ctx.kv.atomic();
  tx.set(pairRequestKey(request.id), request);
  tx.set(pairRequestByTargetKey(target.id, request.id), request.id);
  tx.set(pairRequestByRequesterKey(auth.userId, request.id), request.id);
  const res = await tx.commit();
  if (!res.ok) throw new HubError("Failed to create pair request", "internal", 500);
  return { request };
}

async function findPendingBetween(
  ctx: PairingKvCtx,
  requesterId: string,
  targetId: string,
): Promise<PairRequest | null> {
  const iter = ctx.kv.list<string>({
    prefix: pairRequestsByRequesterPrefix(requesterId),
  });
  for await (const entry of iter) {
    const req = await ctx.kv.get<PairRequest>(pairRequestKey(entry.value));
    if (
      req.value &&
      req.value.status === "pending" &&
      req.value.target_user_id === targetId
    ) {
      return req.value;
    }
  }
  return null;
}

export async function listPendingPairRequests(
  ctx: PairingKvCtx,
  auth: AuthContext,
): Promise<{ incoming: PairRequest[]; outgoing: PairRequest[] }> {
  const incoming: PairRequest[] = [];
  const outgoing: PairRequest[] = [];

  const inIter = ctx.kv.list<string>({
    prefix: pairRequestsByTargetPrefix(auth.userId),
  });
  for await (const entry of inIter) {
    const req = await ctx.kv.get<PairRequest>(pairRequestKey(entry.value));
    if (req.value?.status === "pending") incoming.push(req.value);
  }

  const outIter = ctx.kv.list<string>({
    prefix: pairRequestsByRequesterPrefix(auth.userId),
  });
  for await (const entry of outIter) {
    const req = await ctx.kv.get<PairRequest>(pairRequestKey(entry.value));
    if (req.value?.status === "pending") outgoing.push(req.value);
  }

  incoming.sort((a, b) => b.created_at.localeCompare(a.created_at));
  outgoing.sort((a, b) => b.created_at.localeCompare(a.created_at));
  return { incoming, outgoing };
}

export async function approvePairRequest(
  ctx: PairingKvCtx,
  auth: AuthContext,
  requestId: string,
): Promise<{ contact: Contact; thread: ThreadMeta; request: PairRequest }> {
  const reqRes = await ctx.kv.get<PairRequest>(pairRequestKey(requestId));
  const request = reqRes.value;
  if (!request || request.target_user_id !== auth.userId) {
    throw notFound("Pair request");
  }
  if (request.status !== "pending") {
    throw new HubError("Request already resolved", "conflict", 409);
  }

  const existing = await findExternalLinkBetween(
    ctx,
    request.requester_user_id,
    request.target_user_id,
  );
  if (existing) {
    throw new HubError("Already connected", "conflict", 409);
  }

  const alice = await ctx.getUser(request.target_user_id);
  const bob = await ctx.getUser(request.requester_user_id);
  if (!alice?.handle || !bob?.handle) throw notFound("User");

  const ts = nowIso();
  const linkId = crypto.randomUUID();
  const threadId = crypto.randomUUID();
  const systemMsgId = crypto.randomUUID();
  const introMsgId = request.intro ? crypto.randomUUID() : null;

  const link: ExternalContactLink = {
    id: linkId,
    user_a_id: alice.id,
    user_a_handle: alice.handle,
    user_b_id: bob.id,
    user_b_handle: bob.handle,
    created_at: ts,
    thread_id: threadId,
  };

  const thread: ThreadMeta = {
    id: threadId,
    kind: "direct",
    status: "open",
    from: bob.handle,
    from_user_id: bob.id,
    audience: alice.handle,
    org_id: alice.org_id!,
    participant_count: 2,
    reply_count: introMsgId ? 1 : 0,
    created_at: ts,
    updated_at: ts,
    encryption_mode: "app_envelope",
    external_link_id: linkId,
    participant_user_ids: [alice.id, bob.id],
  };

  const systemPayload = {
    version: 1 as const,
    subject: "Connected",
    notes:
      `${bob.handle} and ${alice.handle} connected via mutande external contact`,
    ping_kind: "thread" as const,
  };
  const systemRecord = await buildAppEnvelopeRecord({
    threadId,
    messageId: systemMsgId,
    fromUserId: "system",
    createdAt: ts,
    payload: systemPayload,
  });

  const systemMessage: ThreadMessage = {
    id: systemMsgId,
    thread_id: threadId,
    from_user_id: "system",
    from_handle: "mutande",
    content_store: "app_envelope",
    created_at: ts,
  };

  const resolved: PairRequest = {
    ...request,
    status: "approved",
    resolved_at: ts,
  };

  const tx = ctx.kv.atomic();
  tx.set(externalLinkKey(linkId), link);
  tx.set(externalLinkPairKey(alice.id, bob.id), linkId);
  tx.set(externalLinkByUserKey(alice.id, linkId), linkId);
  tx.set(externalLinkByUserKey(bob.id, linkId), linkId);
  tx.set(ctx.threadKey(threadId), thread);
  tx.set(ctx.messageKey(threadId, systemMsgId), systemMessage);
  tx.set(
    ["app_envelopes", threadId, systemMsgId],
    systemRecord,
  );
  tx.set(ctx.inboxKey(alice.id, threadId), {
    thread_id: threadId,
    your_status: "pending",
    role: "recipient",
    updated_at: ts,
  });
  tx.set(ctx.inboxKey(bob.id, threadId), {
    thread_id: threadId,
    your_status: "replied",
    role: "sender",
    updated_at: ts,
  });
  tx.set(pairRequestKey(request.id), resolved);

  if (introMsgId && request.intro) {
    const introPayload = {
      version: 1 as const,
      subject: "Introduction",
      notes: request.intro,
    };
    const introRecord = await buildAppEnvelopeRecord({
      threadId,
      messageId: introMsgId,
      fromUserId: bob.id,
      createdAt: ts,
      payload: introPayload,
    });
    const introMessage: ThreadMessage = {
      id: introMsgId,
      thread_id: threadId,
      from_user_id: bob.id,
      from_handle: bob.handle,
      content_store: "app_envelope",
      parent_message_id: systemMsgId,
      created_at: ts,
    };
    tx.set(ctx.messageKey(threadId, introMsgId), introMessage);
    tx.set(["app_envelopes", threadId, introMsgId], introRecord);
  }

  const commit = await tx.commit();
  if (!commit.ok) {
    throw new HubError("Failed to approve pair request", "internal", 500);
  }

  // Invalidate PIN after successful pair (optional hygiene — rotate stays available).
  // Keep PIN so alice can pair with others; do not clear.

  const devices = await ctx.listDevicesForUser(bob.id);
  return {
    contact: {
      handle: bob.handle,
      pubkey: devices[0]?.pubkey ?? null,
      devices,
      kind: "external",
      external_link_id: linkId,
      linked_at: ts,
      thread_id: threadId,
    },
    thread,
    request: resolved,
  };
}

export async function denyPairRequest(
  ctx: PairingKvCtx,
  auth: AuthContext,
  requestId: string,
): Promise<{ ok: true }> {
  const reqRes = await ctx.kv.get<PairRequest>(pairRequestKey(requestId));
  const request = reqRes.value;
  if (!request || request.target_user_id !== auth.userId) {
    throw notFound("Pair request");
  }
  if (request.status !== "pending") {
    throw new HubError("Request already resolved", "conflict", 409);
  }

  const ts = nowIso();
  const resolved: PairRequest = {
    ...request,
    status: "denied",
    resolved_at: ts,
  };

  // Per-user block: alice blocks bob.
  await ctx.kv.set(
    pairBlockKey(auth.userId, normalizeHandle(request.requester_handle)),
    { created_at: ts, requester_handle: request.requester_handle },
  );
  await ctx.kv.set(pairRequestKey(request.id), resolved);

  // Ops signal: ≥5 denies from different users in 7d on same target.
  const denyId = crypto.randomUUID();
  await ctx.kv.set(pairDenyKey(request.target_handle, denyId), {
    requester_handle: request.requester_handle,
    requester_user_id: request.requester_user_id,
    created_at: ts,
  });
  await maybeRaiseOpsFlag(ctx, request);

  return { ok: true };
}

async function maybeRaiseOpsFlag(
  ctx: PairingKvCtx,
  request: PairRequest,
): Promise<void> {
  const cut = Date.now() - PAIR_DENY_OPS_WINDOW_MS;
  const requesters = new Set<string>();
  const iter = ctx.kv.list<{
    requester_handle: string;
    created_at: string;
  }>({ prefix: pairDeniesPrefix(request.target_handle) });
  for await (const entry of iter) {
    if (!entry.value) continue;
    if (Date.parse(entry.value.created_at) < cut) continue;
    requesters.add(normalizeHandle(entry.value.requester_handle));
  }
  if (requesters.size < PAIR_DENY_OPS_THRESHOLD) return;

  // Avoid duplicate flags for same target within window.
  const flagIter = ctx.kv.list<PairingOpsFlag>({
    prefix: pairingOpsFlagsPrefix(),
  });
  for await (const entry of flagIter) {
    const f = entry.value;
    if (
      f &&
      f.target_handle === request.target_handle &&
      Date.parse(f.created_at) >= cut
    ) {
      return;
    }
  }

  const flag: PairingOpsFlag = {
    id: crypto.randomUUID(),
    type: "pairing_harassment",
    target_handle: request.target_handle,
    target_user_id: request.target_user_id,
    deny_count: requesters.size,
    distinct_requesters: [...requesters].sort(),
    created_at: nowIso(),
    window_days: 7,
  };
  await ctx.kv.set(pairingOpsFlagKey(flag.id), flag);
}

export async function listPairingOpsFlags(
  ctx: PairingKvCtx,
): Promise<{ flags: PairingOpsFlag[] }> {
  const flags: PairingOpsFlag[] = [];
  const iter = ctx.kv.list<PairingOpsFlag>({ prefix: pairingOpsFlagsPrefix() });
  for await (const entry of iter) {
    if (entry.value) flags.push(entry.value);
  }
  flags.sort((a, b) => b.created_at.localeCompare(a.created_at));
  return { flags };
}

export async function unpairExternalContact(
  ctx: PairingKvCtx,
  auth: AuthContext,
  linkId: string,
): Promise<{ ok: true; closed_thread_ids: string[] }> {
  const linkRes = await ctx.kv.get<ExternalContactLink>(externalLinkKey(linkId));
  const link = linkRes.value;
  if (!link) throw notFound("External contact");
  if (link.user_a_id !== auth.userId && link.user_b_id !== auth.userId) {
    throw forbidden("Not a party to this link");
  }

  const closed: string[] = [];
  // Close shared threads that reference this link.
  // Scan both inboxes for threads with this external_link_id.
  for (const uid of [link.user_a_id, link.user_b_id]) {
    const inboxIter = ctx.kv.list<{ thread_id: string }>({
      prefix: ["inbox", uid],
    });
    for await (const entry of inboxIter) {
      const tid = entry.value?.thread_id;
      if (!tid) continue;
      const tRes = await ctx.kv.get<ThreadMeta>(ctx.threadKey(tid));
      const thread = tRes.value;
      if (!thread || thread.external_link_id !== linkId) continue;
      if (thread.status === "open") {
        await ctx.kv.set(ctx.threadKey(tid), {
          ...thread,
          status: "closed",
          updated_at: nowIso(),
        });
        closed.push(tid);
      }
    }
  }

  const tx = ctx.kv.atomic();
  tx.delete(externalLinkKey(linkId));
  tx.delete(externalLinkPairKey(link.user_a_id, link.user_b_id));
  tx.delete(externalLinkByUserKey(link.user_a_id, linkId));
  tx.delete(externalLinkByUserKey(link.user_b_id, linkId));
  // Mutual deny-block so re-pair requires clearing? PRD: "a deny-block from either
  // side prevents it". Unpair itself is not deny — re-pairing allowed with fresh PIN.
  await tx.commit();

  return { ok: true, closed_thread_ids: [...new Set(closed)] };
}

export async function assertExternalLinkVelocity(
  ctx: PairingKvCtx,
  linkId: string,
): Promise<void> {
  const day = utcDay();
  const key = externalLinkMsgCountKey(linkId, day);
  const res = await ctx.kv.get<number>(key);
  const count = res.value ?? 0;
  if (count >= EXTERNAL_LINK_MSGS_PER_DAY) {
    throw new HubError(
      "Daily message limit reached for this external contact",
      "rate_limited",
      429,
    );
  }
  await ctx.kv.set(key, count + 1);
}

/** Exported for tests — pin QR builder. */
export { buildPairingQrUri, generateSixDigitPin, pairingFailed };
