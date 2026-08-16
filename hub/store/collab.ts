/**
 * Collab boards — hub-visible container of threads (cards).
 *
 * Invariants are enforced here (not schema comments):
 * - roster ⊆ steerers (adding an agent auto-adds its human)
 * - encryption_mode from participants at creation
 * - instructions XOR instructions_sealed by mode
 * - downgrade_point nullable and immutable once set
 * - steerer_joins append-only; removal is forward-only
 * - roster unique per agent_id
 * - card_count derived
 * - lane_position midpoint inserts + rebalance
 * - set_lane never touches thread status; close_thread never touches lane
 * - memory thread inherits collab encryption_mode
 * - add_learning: creator's side only; reject hosted transports on e2e
 * - status missing|"open" = active; archived boards are hidden and frozen
 * - approved paired externals may steer; cross-org forces app_envelope
 * - schema_version: 1
 */

import {
  HubError,
  conflict,
  envelopeTooLarge,
  forbidden,
  notFound,
} from "./errors.ts";
import {
  formatDisplayAddress,
  parseDisplayAddress,
  parseUserHandle,
} from "./address.ts";
import type {
  AddCollabArtifactsInput,
  AddLearningInput,
  AddRosterInput,
  AddSteererInput,
  Agent,
  ApplyCollabDowngradeInput,
  AuthContext,
  Collab,
  CollabArtifact,
  CollabArtifactInput,
  CollabArtifactView,
  CollabCardStats,
  CollabCardSummary,
  CollabChecklistItem,
  CollabLearning,
  CollabList,
  CollabPendingMembership,
  CollabPortfolio,
  CollabPortfolioRecent,
  CollabRosterEntry,
  CollabStatus,
  CollabView,
  CreateCollabInput,
  InboxEntry,
  ListCollabsOpts,
  RemoveRosterInput,
  RemoveSteererInput,
  RenameCollabListInput,
  SetLaneInput,
  ThreadEncryptionMode,
  ThreadMessage,
  ThreadMeta,
  UpdateCollabInstructionsInput,
  User,
} from "./types.ts";
import { MAX_ENVELOPE_BYTES } from "./types.ts";

export const COLLAB_SCHEMA_VERSION = 1 as const;
export const LANE_GAP = 1024;
export const LANE_MIN_GAP = 1e-6;
export const DEFAULT_LIST_NAMES = ["Backlog", "Doing", "Done"] as const;
export const MAX_COLLAB_ARTIFACTS = 32;

export type CollabKvCtx = {
  kv: Deno.Kv;
  getUser: (id: string) => Promise<User | null>;
  getUserByHandle: (handle: string) => Promise<User | null>;
  getAgent: (id: string) => Promise<Agent | null>;
  resolveAgentForUser: (userId: string, slug?: string) => Promise<Agent>;
  hasApprovedExternalContact: (
    userId: string,
    otherHandle: string,
  ) => Promise<boolean>;
  resolveUserForHandle: (
    authUserId: string,
    handle: string,
  ) => Promise<User | null>;
  collabKey: (id: string) => Deno.KvKey;
  orgCollabKey: (orgId: string, id: string) => Deno.KvKey;
  orgCollabsPrefix: (orgId: string) => Deno.KvKey;
  userCollabKey: (userId: string, collabId: string) => Deno.KvKey;
  userCollabsPrefix: (userId: string) => Deno.KvKey;
  collabThreadKey: (collabId: string, threadId: string) => Deno.KvKey;
  collabThreadsPrefix: (collabId: string) => Deno.KvKey;
  collabArtifactKey: (collabId: string, artifactId: string) => Deno.KvKey;
  collabArtifactsPrefix: (collabId: string) => Deno.KvKey;
  threadKey: (id: string) => Deno.KvKey;
  messageKey: (threadId: string, messageId: string) => Deno.KvKey;
  messagesPrefix: (threadId: string) => Deno.KvKey;
  inboxKey: (userId: string, threadId: string) => Deno.KvKey;
  appEnvelopeKey: (threadId: string, messageId: string) => Deno.KvKey;
  normalizeThread: (t: ThreadMeta) => ThreadMeta;
  nowIso: () => string;
};

function clipName(value: string, field: string, max: number): string {
  const trimmed = value?.trim() ?? "";
  if (!trimmed) {
    throw new HubError(`${field} is required`, "invalid_argument", 400);
  }
  if (trimmed.length > max) {
    throw new HubError(`${field} too long (max ${max})`, "invalid_argument", 400);
  }
  return trimmed;
}

export function assertHttpUrl(raw: string): string {
  const trimmed = raw?.trim() ?? "";
  if (!trimmed) {
    throw new HubError("url is required", "invalid_argument", 400);
  }
  if (trimmed.length > 2048) {
    throw new HubError("url too long (max 2048)", "invalid_argument", 400);
  }
  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    throw new HubError("url is invalid", "invalid_argument", 400);
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new HubError("url must be http or https", "invalid_argument", 400);
  }
  return trimmed;
}

function labelFromUrl(url: string): string {
  try {
    const host = new URL(url).hostname.replace(/^www\./, "");
    return host || "link";
  } catch {
    return "link";
  }
}

function assertArtifactPayloadSize(value: unknown): void {
  const size = new TextEncoder().encode(JSON.stringify(value)).byteLength;
  if (size > MAX_ENVELOPE_BYTES) throw envelopeTooLarge(size);
}

/** Normalize one create/add artifact. File bytes stay in envelope/content — never a local path. */
export function normalizeCollabArtifactInput(
  raw: CollabArtifactInput,
  ts: string,
  userId: string,
): CollabArtifact {
  const kind = raw?.kind === "link" ? "link" : raw?.kind === "file" ? "file" : null;
  if (!kind) {
    throw new HubError("artifact kind must be file or link", "invalid_argument", 400);
  }
  const labelHint = (raw.label ?? raw.title ?? "").trim();
  if (kind === "link") {
    const url = assertHttpUrl(raw.url ?? "");
    const label = clipName(labelHint || labelFromUrl(url), "label", 120);
    const artifact: CollabArtifact = {
      id: crypto.randomUUID(),
      kind,
      label,
      url,
      created_at: ts,
      created_by: userId,
    };
    assertArtifactPayloadSize(artifact);
    return artifact;
  }
  const name = clipName(
    ((raw.name ?? labelHint) || "file").trim() || "file",
    "name",
    240,
  );
  const hasEnvelope = raw.envelope != null;
  const content = raw.content?.trim() ? raw.content : undefined;
  if (hasEnvelope && content) {
    throw new HubError(
      "file artifacts cannot include both envelope and content",
      "invalid_argument",
      400,
    );
  }
  if (!hasEnvelope && !content) {
    throw new HubError(
      "file artifacts need envelope or content",
      "invalid_argument",
      400,
    );
  }
  if (hasEnvelope) {
    assertArtifactPayloadSize(raw.envelope);
  }
  const mime = (raw.mime ?? "").trim() || undefined;
  const size = typeof raw.size === "number" && raw.size >= 0
    ? Math.floor(raw.size)
    : undefined;
  const artifact: CollabArtifact = {
    id: crypto.randomUUID(),
    kind,
    label: (labelHint || name).slice(0, 120),
    name,
    ...(mime ? { mime } : {}),
    ...(size != null ? { size } : {}),
    ...(content ? { content } : {}),
    ...(hasEnvelope ? { envelope: raw.envelope } : {}),
    created_at: ts,
    created_by: userId,
  };
  assertArtifactPayloadSize(artifact);
  return artifact;
}

export function normalizeCollabArtifactInputs(
  raw: CollabArtifactInput[] | undefined,
  ts: string,
  userId: string,
): CollabArtifact[] {
  if (raw == null) return [];
  if (!Array.isArray(raw)) {
    throw new HubError("artifacts must be a list", "invalid_argument", 400);
  }
  if (raw.length > MAX_COLLAB_ARTIFACTS) {
    throw new HubError(
      `too many artifacts (max ${MAX_COLLAB_ARTIFACTS})`,
      "invalid_argument",
      400,
    );
  }
  return raw.map((item) => normalizeCollabArtifactInput(item, ts, userId));
}

function stripSealedArtifact(a: CollabArtifact): CollabArtifact {
  const { envelope: _e, content: _c, ...rest } = a;
  return rest;
}

async function listStoredArtifacts(
  ctx: CollabKvCtx,
  collabId: string,
  opts?: { sealed?: boolean },
): Promise<CollabArtifact[]> {
  const out: CollabArtifact[] = [];
  const iter = ctx.kv.list<CollabArtifact>({
    prefix: ctx.collabArtifactsPrefix(collabId),
  });
  for await (const entry of iter) {
    if (!entry.value) continue;
    out.push(opts?.sealed === false ? stripSealedArtifact(entry.value) : entry.value);
  }
  out.sort((a, b) => b.created_at.localeCompare(a.created_at));
  return out;
}

function assertFileArtifactMode(
  mode: ThreadEncryptionMode,
  artifacts: CollabArtifact[],
): void {
  for (const a of artifacts) {
    if (a.kind !== "file") continue;
    if (mode === "e2e") {
      if (!a.envelope) {
        throw new HubError(
          "e2e file artifacts need a sealed envelope",
          "invalid_argument",
          400,
        );
      }
      if (a.content) {
        throw new HubError(
          "e2e file artifacts cannot store plaintext content",
          "invalid_argument",
          400,
        );
      }
    } else if (a.envelope) {
      throw new HubError(
        "app_envelope file artifacts cannot store sealed envelopes",
        "invalid_argument",
        400,
      );
    } else if (!a.content) {
      throw new HubError(
        "app_envelope file artifacts need content",
        "invalid_argument",
        400,
      );
    }
  }
}

async function artifactsForView(
  ctx: CollabKvCtx,
  collab: Collab,
  opts?: { sealed?: boolean },
): Promise<CollabArtifactView[]> {
  const stored = await listStoredArtifacts(ctx, collab.id, opts);
  const handleCache = new Map<string, string>();
  const views: CollabArtifactView[] = [];
  for (const a of stored) {
    let handle = handleCache.get(a.created_by);
    if (handle == null) {
      const user = await ctx.getUser(a.created_by);
      handle = (user?.handle ?? "").toLowerCase();
      handleCache.set(a.created_by, handle);
    }
    views.push({ ...a, from_handle: handle });
  }
  return views;
}

export function collabKey(id: string): Deno.KvKey {
  return ["collabs", id];
}
export function orgCollabKey(orgId: string, id: string): Deno.KvKey {
  return ["org_collabs", orgId, id];
}
export function orgCollabsPrefix(orgId: string): Deno.KvKey {
  return ["org_collabs", orgId];
}
export function userCollabKey(userId: string, collabId: string): Deno.KvKey {
  return ["user_collabs", userId, collabId];
}
export function userCollabsPrefix(userId: string): Deno.KvKey {
  return ["user_collabs", userId];
}
export function collabThreadKey(collabId: string, threadId: string): Deno.KvKey {
  return ["collab_threads", collabId, threadId];
}
export function collabThreadsPrefix(collabId: string): Deno.KvKey {
  return ["collab_threads", collabId];
}
export function collabArtifactKey(collabId: string, artifactId: string): Deno.KvKey {
  return ["collab_artifacts", collabId, artifactId];
}
export function collabArtifactsPrefix(collabId: string): Deno.KvKey {
  return ["collab_artifacts", collabId];
}

export function insertLanePosition(
  before?: number,
  after?: number,
): number {
  if (before == null && after == null) return LANE_GAP;
  if (before == null) {
    return after! > LANE_GAP ? after! - LANE_GAP : after! / 2;
  }
  if (after == null) return before + LANE_GAP;
  return (before + after) / 2;
}

export function laneGapExhausted(before?: number, after?: number): boolean {
  if (before == null || after == null) return false;
  return (after - before) < LANE_MIN_GAP;
}

export function rebalancePositions(count: number): number[] {
  return Array.from({ length: count }, (_, i) => (i + 1) * LANE_GAP);
}

/** Reject wrong/both instruction payloads for the collab encryption mode. */
export function assertInstructionsXor(
  mode: ThreadEncryptionMode,
  instructions?: string,
  sealed?: { envelope_id: string; updated_by: string },
): void {
  const hasPlain = instructions !== undefined;
  const hasSealed = sealed !== undefined;
  if (hasPlain && hasSealed) {
    throw new HubError(
      "instructions and instructions_sealed cannot both be set",
      "invalid_argument",
      400,
    );
  }
  if (mode === "e2e" && hasPlain) {
    throw new HubError(
      "e2e collabs cannot store plaintext instructions",
      "invalid_argument",
      400,
    );
  }
  if (mode === "app_envelope" && hasSealed) {
    throw new HubError(
      "app_envelope collabs cannot store sealed instructions",
      "invalid_argument",
      400,
    );
  }
}

export function isCollabSteerer(collab: Collab, userId: string): boolean {
  return collab.steerer_user_ids.includes(userId);
}

export function isCreatorSide(collab: Collab, userId: string): boolean {
  return collab.created_by === userId;
}

function defaultLists(): CollabList[] {
  return DEFAULT_LIST_NAMES.map((name, i) => ({
    id: crypto.randomUUID(),
    name,
    position: i,
  }));
}

/** Match a board list by id or case-insensitive name (`Doing`). Empty → first list. */
export function resolveLaneId(
  lists: { id: string; name: string }[],
  lane?: string,
): string | undefined {
  if (!lists.length) return undefined;
  const raw = lane?.trim() ?? "";
  if (!raw) return lists[0].id;
  const lower = raw.toLowerCase();
  const match = lists.find(
    (l) => l.id === raw || l.id.toLowerCase() === lower ||
      l.name.trim().toLowerCase() === lower,
  );
  return match?.id;
}

async function loadCollab(ctx: CollabKvCtx, id: string): Promise<Collab | null> {
  const res = await ctx.kv.get<Collab>(ctx.collabKey(id));
  return res.value ?? null;
}

export function collabStatus(collab: Collab): CollabStatus {
  return collab.status === "archived" ? "archived" : "open";
}

export function isCollabArchived(collab: Collab): boolean {
  return collabStatus(collab) === "archived";
}

function assertMember(collab: Collab, auth: AuthContext): void {
  if (!isCollabSteerer(collab, auth.userId)) {
    throw notFound("Collab");
  }
}

function assertNotArchived(collab: Collab): void {
  if (isCollabArchived(collab)) {
    throw conflict("this collab is archived");
  }
}

function indexUserCollab(
  tx: Deno.AtomicOperation,
  ctx: CollabKvCtx,
  userId: string,
  collabId: string,
): void {
  tx.set(ctx.userCollabKey(userId, collabId), collabId);
}

function dropUserCollab(
  tx: Deno.AtomicOperation,
  ctx: CollabKvCtx,
  userId: string,
  collabId: string,
): void {
  tx.delete(ctx.userCollabKey(userId, collabId));
}

/** Same-org, or an approved paired external. Returns true when the user is external. */
async function assertOrgOrApprovedPair(
  ctx: CollabKvCtx,
  auth: AuthContext,
  user: User,
  forbiddenMsg: string,
): Promise<boolean> {
  if (user.org_id === auth.orgId) return false;
  const handle = (user.handle ?? "").trim().toLowerCase();
  if (!handle) throw notFound("User");
  const ok = await ctx.hasApprovedExternalContact(auth.userId, handle);
  if (!ok) throw forbidden(forbiddenMsg);
  return true;
}

async function resolveRosterEntry(
  ctx: CollabKvCtx,
  auth: AuthContext,
  address: string,
): Promise<CollabRosterEntry> {
  const parsed = parseDisplayAddress(address);
  let userId = auth.userId;
  let slug = parsed.agentSlug;
  if (parsed.kind === "self_agent") {
    slug = parsed.agentSlug;
  } else if (parsed.kind === "user") {
    const handle = formatDisplayAddress(parsed.local, parsed.orgSlug);
    const user = await ctx.resolveUserForHandle(auth.userId, handle);
    if (!user) throw notFound("User");
    await assertOrgOrApprovedPair(
      ctx,
      auth,
      user,
      "Roster agents must be in your org or an approved external contact",
    );
    userId = user.id;
    slug = parsed.agentSlug;
  } else {
    throw new HubError(
      "Roster entries must be agent addresses (alice@acme/claude or @claude)",
      "invalid_argument",
      400,
    );
  }
  if (!slug) {
    throw new HubError(
      "Roster entries need an agent slug — never /default",
      "invalid_argument",
      400,
    );
  }
  if (slug === "default") {
    throw new HubError("Never use /default as an address", "invalid_argument", 400);
  }
  const agent = await ctx.resolveAgentForUser(userId, slug);
  const owner = await ctx.getUser(userId);
  if (!owner?.handle) throw notFound("User");
  const parts = parseUserHandle(owner.handle);
  const display = formatDisplayAddress(parts.local, parts.orgSlug, agent.slug);
  return {
    user_id: userId,
    agent_id: agent.id,
    address: display.toLowerCase(),
    transport: agent.transport,
  };
}

export function deriveEncryptionMode(
  roster: CollabRosterEntry[],
  opts?: { externalCause?: string },
): { mode: ThreadEncryptionMode; cause_address?: string } {
  const external = opts?.externalCause?.trim().toLowerCase();
  if (external) {
    return { mode: "app_envelope", cause_address: external };
  }
  const hosted = roster.find((r) => r.transport === "mcp");
  if (hosted) {
    return { mode: "app_envelope", cause_address: hosted.address };
  }
  return { mode: "e2e" };
}

async function uniqueRoster(
  entries: CollabRosterEntry[],
): Promise<CollabRosterEntry[]> {
  const seen = new Set<string>();
  const out: CollabRosterEntry[] = [];
  for (const e of entries) {
    if (seen.has(e.agent_id)) {
      throw new HubError(
        `Roster already includes agent ${e.address}`,
        "invalid_argument",
        400,
      );
    }
    seen.add(e.agent_id);
    out.push(e);
  }
  return out;
}

function ensureSteerersForRoster(
  steererIds: string[],
  roster: CollabRosterEntry[],
  joins: Collab["steerer_joins"],
  now: string,
): { steerer_user_ids: string[]; steerer_joins: Collab["steerer_joins"] } {
  const ids = [...steererIds];
  const joinList = [...joins];
  for (const r of roster) {
    if (!ids.includes(r.user_id)) {
      ids.push(r.user_id);
      joinList.push({ user_id: r.user_id, joined_at: now });
    }
  }
  return { steerer_user_ids: ids, steerer_joins: joinList };
}

async function steererHandle(
  ctx: CollabKvCtx,
  userId: string,
): Promise<string> {
  const user = await ctx.getUser(userId);
  return (user?.handle ?? userId).toLowerCase();
}

async function createMemoryThread(
  ctx: CollabKvCtx,
  auth: AuthContext,
  mode: ThreadEncryptionMode,
  steererIds: string[],
  ts: string,
): Promise<string> {
  const threadId = crypto.randomUUID();
  const creator = await ctx.getUser(auth.userId);
  const handle = (creator?.handle ?? "unknown").toLowerCase();
  const thread: ThreadMeta = {
    id: threadId,
    kind: "direct",
    status: "open",
    from: handle,
    from_user_id: auth.userId,
    audience: handle,
    org_id: auth.orgId,
    participant_count: steererIds.length,
    reply_count: 0,
    encryption_mode: mode,
    participant_user_ids: [...steererIds],
    created_at: ts,
    updated_at: ts,
  };
  const tx = ctx.kv.atomic();
  tx.set(ctx.threadKey(threadId), thread);
  for (const uid of steererIds) {
    tx.set(ctx.inboxKey(uid, threadId), {
      thread_id: threadId,
      your_status: "replied",
      role: uid === auth.userId ? "sender" : "recipient",
      updated_at: ts,
    } satisfies InboxEntry);
  }
  const res = await tx.commit();
  if (!res.ok) {
    throw new HubError("Failed to create memory thread", "internal", 500);
  }
  return threadId;
}

export async function createCollab(
  ctx: CollabKvCtx,
  auth: AuthContext,
  input: CreateCollabInput,
): Promise<CollabView> {
  const name = clipName(input.name, "name", 120);
  const ts = ctx.nowIso();

  const steererIds = [auth.userId];
  const joins: Collab["steerer_joins"] = [
    { user_id: auth.userId, joined_at: ts },
  ];
  let externalCause: string | undefined;
  for (const raw of input.steerer_handles ?? []) {
    const handle = raw.trim().toLowerCase();
    if (!handle) continue;
    const parsed = parseDisplayAddress(handle);
    if (parsed.kind !== "user" || parsed.agentSlug) {
      throw new HubError(
        "Steerers are human handles (alice@acme), not agent addresses",
        "invalid_argument",
        400,
      );
    }
    const user = await ctx.resolveUserForHandle(
      auth.userId,
      formatDisplayAddress(parsed.local, parsed.orgSlug),
    );
    if (!user) throw notFound("User");
    const isExternal = await assertOrgOrApprovedPair(
      ctx,
      auth,
      user,
      "Steerers must be in your org or an approved external contact",
    );
    if (isExternal && !externalCause) {
      externalCause = (user.handle ?? handle).toLowerCase();
    }
    if (!steererIds.includes(user.id)) {
      steererIds.push(user.id);
      joins.push({ user_id: user.id, joined_at: ts });
    }
  }

  const rosterRaw: CollabRosterEntry[] = [];
  for (const addr of input.roster_addresses ?? []) {
    rosterRaw.push(await resolveRosterEntry(ctx, auth, addr));
  }
  const roster = await uniqueRoster(rosterRaw);
  const membership = ensureSteerersForRoster(steererIds, roster, joins, ts);

  if (!externalCause) {
    for (const uid of membership.steerer_user_ids) {
      const user = await ctx.getUser(uid);
      if (user && user.org_id !== auth.orgId) {
        externalCause = (user.handle ?? uid).toLowerCase();
        break;
      }
    }
  }

  const { mode } = deriveEncryptionMode(roster, { externalCause });
  assertInstructionsXor(mode, input.instructions, input.instructions_sealed);
  const artifacts = normalizeCollabArtifactInputs(
    input.artifacts,
    ts,
    auth.userId,
  );
  assertFileArtifactMode(mode, artifacts);

  const id = crypto.randomUUID();
  const memoryThreadId = await createMemoryThread(
    ctx,
    auth,
    mode,
    membership.steerer_user_ids,
    ts,
  );

  const collab: Collab = {
    id,
    org_id: auth.orgId,
    name,
    encryption_mode: mode,
    steerer_user_ids: membership.steerer_user_ids,
    steerer_joins: membership.steerer_joins,
    roster,
    lists: defaultLists(),
    memory_thread_id: memoryThreadId,
    schema_version: COLLAB_SCHEMA_VERSION,
    created_by: auth.userId,
    created_at: ts,
    updated_at: ts,
    ...(mode === "app_envelope" && input.instructions !== undefined
      ? { instructions: input.instructions }
      : {}),
    ...(mode === "e2e" && input.instructions_sealed
      ? { instructions_sealed: input.instructions_sealed }
      : {}),
  };

  const tx = ctx.kv.atomic();
  tx.set(ctx.collabKey(id), collab);
  tx.set(ctx.orgCollabKey(auth.orgId, id), id);
  for (const uid of membership.steerer_user_ids) {
    indexUserCollab(tx, ctx, uid, id);
  }
  for (const artifact of artifacts) {
    tx.set(ctx.collabArtifactKey(id, artifact.id), artifact);
  }
  const res = await tx.commit();
  if (!res.ok) {
    throw new HubError("Failed to create collab", "internal", 500);
  }
  return viewCollab(ctx, auth, collab);
}

export function laneBucket(
  collab: Collab,
  laneId?: string,
): "backlog" | "doing" | "done" {
  if (!laneId) return "backlog";
  const list = collab.lists.find((l) => l.id === laneId);
  if (!list) return "backlog";
  const name = list.name.trim().toLowerCase();
  if (name === "doing") return "doing";
  if (name === "done") return "done";
  if (name === "backlog") return "backlog";
  const sorted = [...collab.lists].sort((a, b) => a.position - b.position);
  const idx = sorted.findIndex((l) => l.id === laneId);
  if (idx <= 0) return "backlog";
  if (idx === sorted.length - 1) return "done";
  return "doing";
}

function utcDateKey(iso: string): string | null {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString().slice(0, 10);
}

export function last84ActivityDays(
  counts: Map<string, number>,
  now = new Date(),
): { date: string; count: number }[] {
  const out: { date: string; count: number }[] = [];
  const todayUtc = Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate(),
  );
  for (let i = 83; i >= 0; i--) {
    const key = new Date(todayUtc - i * 86_400_000).toISOString().slice(0, 10);
    out.push({ date: key, count: counts.get(key) ?? 0 });
  }
  return out;
}

const RECENT_FEED_LIMIT = 6;

type RecentCardSeed = Omit<
  CollabPortfolioRecent,
  "collab_id" | "collab_name"
>;

function emptyPortfolio(collabCount = 0): CollabPortfolio {
  return {
    activity: last84ActivityDays(new Map()),
    lane_totals: { backlog: 0, doing: 0, done: 0 },
    totals: { collabs: collabCount, open: 0, doing: 0, needs_you: 0 },
    recent: [],
  };
}

async function summarizeCollabCards(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collab: Collab,
): Promise<
  CollabCardStats & { activity: Map<string, number>; recent: RecentCardSeed[] }
> {
  const stats: CollabCardStats & {
    activity: Map<string, number>;
    recent: RecentCardSeed[];
  } = {
    card_count: 0,
    open: 0,
    closed: 0,
    backlog: 0,
    doing: 0,
    done: 0,
    needs_you: 0,
    activity: new Map(),
    recent: [],
  };
  const iter = ctx.kv.list<string>({
    prefix: ctx.collabThreadsPrefix(collab.id),
  });
  for await (const entry of iter) {
    const threadRes = await ctx.kv.get<ThreadMeta>(ctx.threadKey(entry.value));
    const thread = threadRes.value ? ctx.normalizeThread(threadRes.value) : null;
    if (!thread) continue;
    stats.card_count += 1;
    const isOpen = thread.status === "open";
    if (isOpen) stats.open += 1;
    else stats.closed += 1;
    if (isOpen) {
      stats[laneBucket(collab, thread.lane_id)] += 1;
    }
    let needsYou = false;
    if (isOpen) {
      const inbox = await ctx.kv.get<InboxEntry>(
        ctx.inboxKey(auth.userId, thread.id),
      );
      needsYou = inbox.value?.your_status === "pending";
      if (needsYou) stats.needs_you += 1;
    }
    if (
      !stats.last_updated_at ||
      thread.updated_at > stats.last_updated_at
    ) {
      stats.last_updated_at = thread.updated_at;
    }
    const day = utcDateKey(thread.updated_at);
    if (day) {
      stats.activity.set(day, (stats.activity.get(day) ?? 0) + 1);
    }
    const subject = thread.last_subject?.trim();
    stats.recent.push({
      thread_id: thread.id,
      from: thread.from,
      audience: thread.audience,
      last_subject: subject || undefined,
      updated_at: thread.updated_at,
      needs_you: needsYou,
    });
  }
  return stats;
}

export async function listCollabs(
  ctx: CollabKvCtx,
  auth: AuthContext,
  opts?: ListCollabsOpts,
): Promise<{ collabs: CollabView[]; portfolio: CollabPortfolio }> {
  const wantArchived = opts?.archived === true;
  const seen = new Set<string>();
  const ids: string[] = [];
  const orgIter = ctx.kv.list<string>({ prefix: ctx.orgCollabsPrefix(auth.orgId) });
  for await (const entry of orgIter) {
    if (seen.has(entry.value)) continue;
    seen.add(entry.value);
    ids.push(entry.value);
  }
  const userIter = ctx.kv.list<string>({
    prefix: ctx.userCollabsPrefix(auth.userId),
  });
  for await (const entry of userIter) {
    if (seen.has(entry.value)) continue;
    seen.add(entry.value);
    ids.push(entry.value);
  }

  const collabs: CollabView[] = [];
  const activity = new Map<string, number>();
  const recent: CollabPortfolioRecent[] = [];
  const laneTotals = { backlog: 0, doing: 0, done: 0 };
  let open = 0;
  let doing = 0;
  let needsYou = 0;
  for (const id of ids) {
    const collab = await loadCollab(ctx, id);
    if (!collab) continue;
    if (!isCollabSteerer(collab, auth.userId)) continue;
    if (wantArchived !== isCollabArchived(collab)) continue;
    const stats = await summarizeCollabCards(ctx, auth, collab);
    for (const [date, count] of stats.activity) {
      activity.set(date, (activity.get(date) ?? 0) + count);
    }
    for (const card of stats.recent) {
      recent.push({
        ...card,
        collab_id: collab.id,
        collab_name: collab.name,
      });
    }
    open += stats.open;
    doing += stats.doing;
    needsYou += stats.needs_you;
    laneTotals.backlog += stats.backlog;
    laneTotals.doing += stats.doing;
    laneTotals.done += stats.done;
    const steerers = await Promise.all(
      collab.steerer_user_ids.map(async (user_id) => ({
        user_id,
        handle: await steererHandle(ctx, user_id),
      })),
    );
    collabs.push({
      ...collab,
      card_count: stats.card_count,
      open: stats.open,
      backlog: stats.backlog,
      doing: stats.doing,
      done: stats.done,
      needs_you: stats.needs_you,
      last_card_updated_at: stats.last_updated_at,
      cards: [],
      learnings: [],
      artifacts: await artifactsForView(ctx, collab, { sealed: false }),
      steerers,
    });
  }
  collabs.sort((a, b) => b.updated_at.localeCompare(a.updated_at));
  if (collabs.length === 0) {
    return { collabs, portfolio: emptyPortfolio(0) };
  }
  recent.sort((a, b) => b.updated_at.localeCompare(a.updated_at));
  return {
    collabs,
    portfolio: {
      activity: last84ActivityDays(activity),
      lane_totals: laneTotals,
      totals: {
        collabs: collabs.length,
        open,
        doing,
        needs_you: needsYou,
      },
      recent: recent.slice(0, RECENT_FEED_LIMIT),
    },
  };
}

export async function getCollab(
  ctx: CollabKvCtx,
  auth: AuthContext,
  id: string,
): Promise<CollabView> {
  const collab = await loadCollab(ctx, id);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  return viewCollab(ctx, auth, collab);
}

async function listCards(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collab: Collab,
): Promise<CollabCardSummary[]> {
  const cards: CollabCardSummary[] = [];
  const iter = ctx.kv.list<string>({
    prefix: ctx.collabThreadsPrefix(collab.id),
  });
  for await (const entry of iter) {
    const threadRes = await ctx.kv.get<ThreadMeta>(ctx.threadKey(entry.value));
    const thread = threadRes.value ? ctx.normalizeThread(threadRes.value) : null;
    if (!thread) continue;
    const inbox = await ctx.kv.get<InboxEntry>(
      ctx.inboxKey(auth.userId, thread.id),
    );
    cards.push({
      id: thread.id,
      lane_id: thread.lane_id,
      lane_position: thread.lane_position,
      assigned_to: thread.assigned_to,
      watchers: thread.watchers,
      tags: thread.tags,
      due_on: thread.due_on,
      checklist: thread.checklist,
      status: thread.status,
      from: thread.from,
      audience: thread.audience,
      updated_at: thread.updated_at,
      your_status: inbox.value?.your_status,
    });
  }
  cards.sort((a, b) => (a.lane_position ?? 0) - (b.lane_position ?? 0));
  return cards;
}

async function listLearnings(
  ctx: CollabKvCtx,
  collab: Collab,
): Promise<CollabLearning[]> {
  const learnings: CollabLearning[] = [];
  const iter = ctx.kv.list<ThreadMessage>({
    prefix: ctx.messagesPrefix(collab.memory_thread_id),
  });
  for await (const entry of iter) {
    const msg = entry.value;
    const payload = msg.app_envelope;
    const isLearning = payload?.intent === "fyi" &&
      (payload as { learning?: boolean }).learning === true;
    if (collab.encryption_mode === "app_envelope") {
      if (!isLearning) continue;
      learnings.push({
        id: msg.id,
        created_at: msg.created_at,
        from_handle: msg.from_handle,
        notes: typeof payload?.notes === "string" ? payload.notes : undefined,
      });
    } else {
      // E2E: hub cannot read notes; surface sealed stubs (daemon decrypts).
      learnings.push({
        id: msg.id,
        created_at: msg.created_at,
        from_handle: msg.from_handle,
        sealed: true,
      });
    }
  }
  learnings.sort((a, b) => a.created_at.localeCompare(b.created_at));
  return learnings;
}

async function viewCollab(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collab: Collab,
  opts?: { cards?: boolean },
): Promise<CollabView> {
  const includeCards = opts?.cards !== false;
  const cards = includeCards ? await listCards(ctx, auth, collab) : [];
  const learnings = includeCards ? await listLearnings(ctx, collab) : [];
  const artifacts = await artifactsForView(ctx, collab, { sealed: true });
  const steerers = await Promise.all(
    collab.steerer_user_ids.map(async (user_id) => ({
      user_id,
      handle: await steererHandle(ctx, user_id),
    })),
  );
  return {
    ...collab,
    card_count: cards.length,
    cards,
    learnings,
    artifacts,
    steerers,
  };
}

export async function setLane(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
  input: SetLaneInput,
): Promise<{ thread: ThreadMeta }> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  assertNotArchived(collab);

  const lane = collab.lists.find((l) => l.id === input.lane_id);
  if (!lane) {
    throw new HubError("Unknown lane", "invalid_argument", 400);
  }

  const threadRes = await ctx.kv.get<ThreadMeta>(ctx.threadKey(input.thread_id));
  const thread = threadRes.value ? ctx.normalizeThread(threadRes.value) : null;
  if (!thread || thread.collab_id !== collabId) throw notFound("Thread");

  const siblings = (await listCards(ctx, auth, collab))
    .filter((c) => c.lane_id === input.lane_id && c.id !== thread.id)
    .sort((a, b) => (a.lane_position ?? 0) - (b.lane_position ?? 0));

  let before: number | undefined;
  let after: number | undefined;
  if (input.before_thread_id) {
    const idx = siblings.findIndex((c) => c.id === input.before_thread_id);
    after = idx >= 0 ? siblings[idx].lane_position : undefined;
    before = idx > 0 ? siblings[idx - 1].lane_position : undefined;
  } else if (input.after_thread_id) {
    const idx = siblings.findIndex((c) => c.id === input.after_thread_id);
    before = idx >= 0 ? siblings[idx].lane_position : undefined;
    after = idx >= 0 && idx < siblings.length - 1
      ? siblings[idx + 1].lane_position
      : undefined;
  } else if (siblings.length > 0) {
    before = siblings[siblings.length - 1].lane_position;
  }

  const status = thread.status;
  let position = insertLanePosition(before, after);
  const needRebalance = laneGapExhausted(before, after) ||
    laneGapExhausted(before, position) ||
    laneGapExhausted(position, after);

  const updated: ThreadMeta = {
    ...thread,
    lane_id: input.lane_id,
    lane_position: position,
    status, // never couple board lane to thread status
    updated_at: ctx.nowIso(),
  };

  const tx = ctx.kv.atomic();
  tx.set(ctx.threadKey(thread.id), updated);

  if (needRebalance) {
    const ordered = [...siblings, { id: thread.id, lane_position: position }]
      .sort((a, b) => (a.lane_position ?? 0) - (b.lane_position ?? 0));
    const positions = rebalancePositions(ordered.length);
    for (let i = 0; i < ordered.length; i++) {
      const id = ordered[i].id;
      if (id === thread.id) {
        updated.lane_position = positions[i];
        tx.set(ctx.threadKey(id), updated);
        continue;
      }
      const sibRes = await ctx.kv.get<ThreadMeta>(ctx.threadKey(id));
      if (!sibRes.value) continue;
      tx.set(ctx.threadKey(id), {
        ...ctx.normalizeThread(sibRes.value),
        lane_position: positions[i],
      });
    }
    position = updated.lane_position ?? position;
  }

  const res = await tx.commit();
  if (!res.ok) {
    throw new HubError("Failed to set lane", "internal", 500);
  }
  return { thread: updated };
}

export async function addLearning(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
  input: AddLearningInput,
): Promise<{ message_id: string }> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  assertNotArchived(collab);

  if (!isCreatorSide(collab, auth.userId)) {
    throw forbidden(
      "Only the collab creator's side may add_learning — propose via reply on the memory thread",
    );
  }

  const notes = clipName(input.notes, "notes", 500);
  const fromAgent = input.from_agent_id
    ? await ctx.getAgent(input.from_agent_id)
    : input.from_agent
    ? await ctx.resolveAgentForUser(auth.userId, input.from_agent)
    : null;

  if (
    collab.encryption_mode === "e2e" &&
    fromAgent?.transport === "mcp"
  ) {
    throw forbidden(
      "Hosted agents cannot write the brain on an E2E collab",
    );
  }

  const sender = await ctx.getUser(auth.userId);
  if (!sender?.handle) throw notFound("User");
  const parts = parseUserHandle(sender.handle);
  const fromHandle = formatDisplayAddress(
    parts.local,
    parts.orgSlug,
    fromAgent?.slug,
  ).toLowerCase();

  const ts = ctx.nowIso();
  const messageId = crypto.randomUUID();
  const threadRes = await ctx.kv.get<ThreadMeta>(
    ctx.threadKey(collab.memory_thread_id),
  );
  const thread = threadRes.value
    ? ctx.normalizeThread(threadRes.value)
    : null;
  if (!thread) throw notFound("Memory thread");

  if (collab.encryption_mode === "e2e") {
    if (!input.envelope) {
      throw new HubError(
        "E2E collabs require a sealed envelope for add_learning",
        "invalid_argument",
        400,
      );
    }
    const msg: ThreadMessage = {
      id: messageId,
      thread_id: collab.memory_thread_id,
      from_user_id: auth.userId,
      from_handle: fromHandle,
      from_agent_id: fromAgent?.id,
      envelope: input.envelope,
      content_store: "e2e",
      created_at: ts,
    };
    const updated: ThreadMeta = {
      ...thread,
      reply_count: thread.reply_count + 1,
      updated_at: ts,
    };
    const tx = ctx.kv.atomic();
    tx.set(ctx.messageKey(collab.memory_thread_id, messageId), msg);
    tx.set(ctx.threadKey(collab.memory_thread_id), updated);
    const res = await tx.commit();
    if (!res.ok) {
      throw new HubError("Failed to add learning", "internal", 500);
    }
    return { message_id: messageId };
  }

  const payload = {
    version: 1,
    intent: "fyi" as const,
    learning: true,
    notes,
  };
  const msg: ThreadMessage = {
    id: messageId,
    thread_id: collab.memory_thread_id,
    from_user_id: auth.userId,
    from_handle: fromHandle,
    from_agent_id: fromAgent?.id,
    app_envelope: payload,
    content_store: "app_envelope",
    created_at: ts,
  };
  const updated: ThreadMeta = {
    ...thread,
    reply_count: thread.reply_count + 1,
    updated_at: ts,
  };
  const tx = ctx.kv.atomic();
  tx.set(ctx.messageKey(collab.memory_thread_id, messageId), msg);
  tx.set(ctx.appEnvelopeKey(collab.memory_thread_id, messageId), {
    thread_id: collab.memory_thread_id,
    message_id: messageId,
    from_user_id: auth.userId,
    from_agent_id: fromAgent?.id,
    created_at: ts,
    payload,
  });
  tx.set(ctx.threadKey(collab.memory_thread_id), updated);
  const res = await tx.commit();
  if (!res.ok) {
    throw new HubError("Failed to add learning", "internal", 500);
  }
  return { message_id: messageId };
}

export async function updateInstructions(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
  input: UpdateCollabInstructionsInput,
): Promise<CollabView> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  if (!isCreatorSide(collab, auth.userId)) {
    throw forbidden("Only the collab creator can edit instructions");
  }
  assertNotArchived(collab);
  assertInstructionsXor(
    collab.encryption_mode,
    input.instructions,
    input.instructions_sealed,
  );
  const updated: Collab = {
    ...collab,
    updated_at: ctx.nowIso(),
  };
  if (collab.encryption_mode === "app_envelope") {
    if (input.instructions !== undefined) updated.instructions = input.instructions;
    delete updated.instructions_sealed;
  } else {
    if (input.instructions_sealed) {
      updated.instructions_sealed = input.instructions_sealed;
    }
    delete updated.instructions;
  }
  await ctx.kv.set(ctx.collabKey(collab.id), updated);
  return viewCollab(ctx, auth, updated, { cards: false });
}

export async function addCollabArtifacts(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
  input: AddCollabArtifactsInput,
): Promise<CollabView> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  assertNotArchived(collab);
  const ts = ctx.nowIso();
  const incoming = normalizeCollabArtifactInputs(input.artifacts, ts, auth.userId);
  if (incoming.length === 0) {
    throw new HubError("artifacts is required", "invalid_argument", 400);
  }
  assertFileArtifactMode(collab.encryption_mode, incoming);
  const existing = await listStoredArtifacts(ctx, collab.id);
  if (existing.length + incoming.length > MAX_COLLAB_ARTIFACTS) {
    throw new HubError(
      `too many artifacts (max ${MAX_COLLAB_ARTIFACTS})`,
      "invalid_argument",
      400,
    );
  }
  const updated: Collab = { ...collab, updated_at: ts };
  const tx = ctx.kv.atomic();
  tx.set(ctx.collabKey(collab.id), updated);
  for (const artifact of incoming) {
    tx.set(ctx.collabArtifactKey(collab.id, artifact.id), artifact);
  }
  const res = await tx.commit();
  if (!res.ok) {
    throw new HubError("Failed to add collab artifacts", "internal", 500);
  }
  return viewCollab(ctx, auth, updated);
}

export async function applyCollabDowngrade(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
  input: ApplyCollabDowngradeInput,
): Promise<CollabView> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  assertNotArchived(collab);
  if (collab.downgrade_point) {
    throw new HubError(
      "downgrade_point is immutable once set",
      "invalid_argument",
      409,
    );
  }
  if (collab.encryption_mode !== "e2e") {
    throw new HubError(
      "Collab is already app_envelope",
      "invalid_argument",
      400,
    );
  }
  const required = [...collab.steerer_user_ids].sort();
  const given = [...new Set(input.approvers)].sort();
  if (
    required.length !== given.length ||
    required.some((id, i) => id !== given[i])
  ) {
    throw forbidden("Downgrade requires unanimous steerer consent");
  }
  const updated: Collab = {
    ...collab,
    encryption_mode: "app_envelope",
    downgrade_point: {
      at: ctx.nowIso(),
      approvers: given,
      cause_address: input.cause_address.trim().toLowerCase(),
    },
    updated_at: ctx.nowIso(),
  };
  delete updated.instructions_sealed;
  await ctx.kv.set(ctx.collabKey(collab.id), updated);
  return viewCollab(ctx, auth, updated, { cards: false });
}

function applyDowngradeToCollab(
  collab: Collab,
  ts: string,
  causeAddress: string,
  approvers: string[],
): Collab {
  const updated: Collab = {
    ...collab,
    encryption_mode: "app_envelope",
    downgrade_point: {
      at: ts,
      approvers: [...approvers],
      cause_address: causeAddress.trim().toLowerCase(),
    },
    updated_at: ts,
  };
  delete updated.instructions_sealed;
  delete updated.pending_membership;
  return updated;
}

async function persistCollab(
  ctx: CollabKvCtx,
  collab: Collab,
  extras?: (tx: Deno.AtomicOperation) => void,
): Promise<void> {
  const tx = ctx.kv.atomic();
  tx.set(ctx.collabKey(collab.id), collab);
  extras?.(tx);
  const res = await tx.commit();
  if (!res.ok) {
    throw new HubError("Failed to update collab", "internal", 500);
  }
}

async function commitAddSteerer(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collab: Collab,
  user: User,
): Promise<CollabView> {
  if (collab.steerer_user_ids.includes(user.id)) {
    return viewCollab(ctx, auth, collab, { cards: false });
  }
  const ts = ctx.nowIso();
  const updated: Collab = {
    ...collab,
    steerer_user_ids: [...collab.steerer_user_ids, user.id],
    steerer_joins: [...collab.steerer_joins, { user_id: user.id, joined_at: ts }],
    updated_at: ts,
  };
  delete updated.pending_membership;
  await persistCollab(ctx, updated, (tx) => {
    indexUserCollab(tx, ctx, user.id, updated.id);
    tx.set(ctx.inboxKey(user.id, updated.memory_thread_id), {
      thread_id: updated.memory_thread_id,
      your_status: "replied",
      role: "recipient",
      updated_at: ts,
    } satisfies InboxEntry);
  });
  return viewCollab(ctx, auth, updated, { cards: false });
}

async function commitAddRoster(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collab: Collab,
  entry: CollabRosterEntry,
): Promise<CollabView> {
  if (collab.roster.some((r) => r.agent_id === entry.agent_id)) {
    return viewCollab(ctx, auth, collab, { cards: false });
  }
  const ts = ctx.nowIso();
  const roster = await uniqueRoster([...collab.roster, entry]);
  const membership = ensureSteerersForRoster(
    collab.steerer_user_ids,
    roster,
    collab.steerer_joins,
    ts,
  );
  const newHumans = membership.steerer_user_ids.filter(
    (id) => !collab.steerer_user_ids.includes(id),
  );
  const updated: Collab = {
    ...collab,
    roster,
    steerer_user_ids: membership.steerer_user_ids,
    steerer_joins: membership.steerer_joins,
    updated_at: ts,
  };
  delete updated.pending_membership;
  await persistCollab(ctx, updated, (tx) => {
    for (const uid of newHumans) {
      indexUserCollab(tx, ctx, uid, updated.id);
      tx.set(ctx.inboxKey(uid, updated.memory_thread_id), {
        thread_id: updated.memory_thread_id,
        your_status: "replied",
        role: "recipient",
        updated_at: ts,
      } satisfies InboxEntry);
    }
  });
  return viewCollab(ctx, auth, updated, { cards: false });
}

async function queueOrApplyMembership(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collab: Collab,
  pending: Omit<CollabPendingMembership, "proposed_by" | "approved_by">,
): Promise<CollabView> {
  if (collab.pending_membership) {
    throw conflict("A membership change is already pending consent");
  }
  const ts = ctx.nowIso();
  if (collab.steerer_user_ids.length === 1) {
    const flipped = applyDowngradeToCollab(
      collab,
      ts,
      pending.cause_address,
      [auth.userId],
    );
    if (pending.kind === "steerer") {
      const user = await ctx.resolveUserForHandle(
        auth.userId,
        pending.handle ?? "",
      );
      if (!user) throw notFound("User");
      return commitAddSteerer(ctx, auth, flipped, user);
    }
    const entry = await resolveRosterEntry(ctx, auth, pending.address ?? "");
    return commitAddRoster(ctx, auth, flipped, entry);
  }
  const stored: CollabPendingMembership = {
    ...pending,
    proposed_by: auth.userId,
    approved_by: [auth.userId],
  };
  const updated: Collab = {
    ...collab,
    pending_membership: stored,
    updated_at: ts,
  };
  await persistCollab(ctx, updated);
  return viewCollab(ctx, auth, updated, { cards: false });
}

export async function addSteerer(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
  input: AddSteererInput,
): Promise<CollabView> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  assertNotArchived(collab);
  const parsed = parseDisplayAddress(input.handle.trim().toLowerCase());
  if (parsed.kind !== "user" || parsed.agentSlug) {
    throw new HubError(
      "Steerers are human handles (alice@acme)",
      "invalid_argument",
      400,
    );
  }
  const handle = formatDisplayAddress(parsed.local, parsed.orgSlug);
  const user = await ctx.resolveUserForHandle(auth.userId, handle);
  if (!user) throw notFound("User");
  const isExternal = await assertOrgOrApprovedPair(
    ctx,
    auth,
    user,
    "Steerers must be in your org or an approved external contact",
  );
  if (collab.steerer_user_ids.includes(user.id)) {
    return viewCollab(ctx, auth, collab, { cards: false });
  }
  if (isExternal && collab.encryption_mode === "e2e") {
    return queueOrApplyMembership(ctx, auth, collab, {
      kind: "steerer",
      handle: (user.handle ?? handle).toLowerCase(),
      cause_address: (user.handle ?? handle).toLowerCase(),
    });
  }
  return commitAddSteerer(ctx, auth, collab, user);
}

export async function removeSteerer(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
  input: RemoveSteererInput,
): Promise<CollabView> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  assertNotArchived(collab);
  if (input.user_id === collab.created_by) {
    throw forbidden("Cannot remove the collab creator");
  }
  if (!collab.steerer_user_ids.includes(input.user_id)) {
    return viewCollab(ctx, auth, collab, { cards: false });
  }
  const ts = ctx.nowIso();
  const updated: Collab = {
    ...collab,
    steerer_user_ids: collab.steerer_user_ids.filter((id) => id !== input.user_id),
    roster: collab.roster.filter((r) => r.user_id !== input.user_id),
    steerer_removals: [
      ...(collab.steerer_removals ?? []),
      { user_id: input.user_id, removed_at: ts },
    ],
    updated_at: ts,
  };
  // Joins stay append-only — do not rewrite history.
  await persistCollab(ctx, updated, (tx) => {
    dropUserCollab(tx, ctx, input.user_id, updated.id);
  });
  return viewCollab(ctx, auth, updated, { cards: false });
}

export async function addRoster(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
  input: AddRosterInput,
): Promise<CollabView> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  assertNotArchived(collab);
  const entry = await resolveRosterEntry(ctx, auth, input.address);
  if (collab.roster.some((r) => r.agent_id === entry.agent_id)) {
    return viewCollab(ctx, auth, collab, { cards: false });
  }
  const owner = await ctx.getUser(entry.user_id);
  const ownerExternal = owner != null && owner.org_id !== auth.orgId;
  const hosted = entry.transport === "mcp";
  if (collab.encryption_mode === "e2e" && (hosted || ownerExternal)) {
    return queueOrApplyMembership(ctx, auth, collab, {
      kind: "roster",
      address: entry.address,
      cause_address: hosted
        ? entry.address
        : (owner?.handle ?? entry.address).toLowerCase(),
    });
  }
  return commitAddRoster(ctx, auth, collab, entry);
}

export async function removeRoster(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
  input: RemoveRosterInput,
): Promise<CollabView> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  assertNotArchived(collab);
  if (!collab.roster.some((r) => r.agent_id === input.agent_id)) {
    return viewCollab(ctx, auth, collab, { cards: false });
  }
  const ts = ctx.nowIso();
  const updated: Collab = {
    ...collab,
    roster: collab.roster.filter((r) => r.agent_id !== input.agent_id),
    updated_at: ts,
  };
  await persistCollab(ctx, updated);
  return viewCollab(ctx, auth, updated, { cards: false });
}

export async function approvePendingMembership(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
): Promise<CollabView> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  assertNotArchived(collab);
  const pending = collab.pending_membership;
  if (!pending) {
    throw new HubError("No pending membership", "invalid_argument", 400);
  }
  const approved = pending.approved_by.includes(auth.userId)
    ? pending.approved_by
    : [...pending.approved_by, auth.userId];
  const required = [...collab.steerer_user_ids].sort();
  const given = [...new Set(approved)].sort();
  const unanimous = required.length === given.length &&
    required.every((id, i) => id === given[i]);
  if (!unanimous) {
    const updated: Collab = {
      ...collab,
      pending_membership: { ...pending, approved_by: approved },
      updated_at: ctx.nowIso(),
    };
    await persistCollab(ctx, updated);
    return viewCollab(ctx, auth, updated, { cards: false });
  }
  const ts = ctx.nowIso();
  const flipped = applyDowngradeToCollab(
    collab,
    ts,
    pending.cause_address,
    given,
  );
  if (pending.kind === "steerer") {
    const user = await ctx.resolveUserForHandle(
      auth.userId,
      pending.handle ?? "",
    );
    if (!user) throw notFound("User");
    return commitAddSteerer(ctx, auth, flipped, user);
  }
  const entry = await resolveRosterEntry(ctx, auth, pending.address ?? "");
  return commitAddRoster(ctx, auth, flipped, entry);
}

export async function denyPendingMembership(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
): Promise<CollabView> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  assertNotArchived(collab);
  if (!collab.pending_membership) {
    throw new HubError("No pending membership", "invalid_argument", 400);
  }
  const updated: Collab = { ...collab, updated_at: ctx.nowIso() };
  delete updated.pending_membership;
  await persistCollab(ctx, updated);
  return viewCollab(ctx, auth, updated, { cards: false });
}

export async function archiveCollab(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
): Promise<CollabView> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  if (isCollabArchived(collab)) {
    return viewCollab(ctx, auth, collab, { cards: false });
  }
  const updated: Collab = {
    ...collab,
    status: "archived",
    updated_at: ctx.nowIso(),
  };
  delete updated.pending_membership;
  await persistCollab(ctx, updated);
  return viewCollab(ctx, auth, updated, { cards: false });
}

export async function unarchiveCollab(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
): Promise<CollabView> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  if (!isCollabArchived(collab)) {
    return viewCollab(ctx, auth, collab, { cards: false });
  }
  const updated: Collab = { ...collab, status: "open", updated_at: ctx.nowIso() };
  await persistCollab(ctx, updated);
  return viewCollab(ctx, auth, updated, { cards: false });
}

export async function renameList(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
  input: RenameCollabListInput,
): Promise<CollabView> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  assertNotArchived(collab);
  const name = clipName(input.name, "name", 60);
  const lists = collab.lists.map((l) =>
    l.id === input.lane_id ? { ...l, name } : l
  );
  if (!lists.some((l) => l.id === input.lane_id)) {
    throw new HubError("Unknown lane", "invalid_argument", 400);
  }
  const updated: Collab = { ...collab, lists, updated_at: ctx.nowIso() };
  await persistCollab(ctx, updated);
  return viewCollab(ctx, auth, updated, { cards: false });
}

export async function nextLanePosition(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collab: Collab,
  laneId: string,
): Promise<number> {
  const cards = await listCards(ctx, auth, collab);
  const inLane = cards
    .filter((c) => c.lane_id === laneId)
    .sort((a, b) => (a.lane_position ?? 0) - (b.lane_position ?? 0));
  if (inLane.length === 0) return LANE_GAP;
  return insertLanePosition(inLane[inLane.length - 1].lane_position, undefined);
}

export async function resolveCollabCardCreate(
  ctx: CollabKvCtx,
  auth: AuthContext,
  collabId: string,
  opts?: {
    lane_id?: string;
    assigned_to?: string;
    watchers?: string[];
    tags?: string[];
    due_on?: string;
    checklist?: CollabChecklistItem[];
  },
): Promise<{
  collab: Collab;
  recipientIds: string[];
  encryptionMode: ThreadEncryptionMode;
  lane_id: string;
  lane_position: number;
  assigned_to?: string;
  watchers?: string[];
  tags?: string[];
  due_on?: string;
  checklist?: CollabChecklistItem[];
}> {
  const collab = await loadCollab(ctx, collabId);
  if (!collab) throw notFound("Collab");
  assertMember(collab, auth);
  assertNotArchived(collab);
  const laneId = resolveLaneId(collab.lists, opts?.lane_id);
  if (!laneId) {
    throw new HubError("Unknown lane", "invalid_argument", 400);
  }
  const lane_position = await nextLanePosition(ctx, auth, collab, laneId);
  const assigned_to = opts?.assigned_to?.trim().toLowerCase() || undefined;
  if (assigned_to) {
    await assertCardAssignee(ctx, collab, assigned_to);
  }
  return {
    collab,
    recipientIds: [...collab.steerer_user_ids],
    encryptionMode: collab.encryption_mode,
    lane_id: laneId,
    lane_position,
    assigned_to,
    watchers: opts?.watchers?.map((w) => w.trim().toLowerCase()).filter(Boolean),
    tags: normalizeCardTags(opts?.tags),
    due_on: normalizeDueOn(opts?.due_on),
    checklist: normalizeChecklist(opts?.checklist),
  };
}

const MAX_CARD_TAGS = 12;
const MAX_CARD_TAG_LEN = 32;
const MAX_CHECKLIST_ITEMS = 24;
const MAX_CHECKLIST_TEXT = 160;

export function normalizeCardTags(raw?: string[]): string[] | undefined {
  if (!raw?.length) return undefined;
  const out: string[] = [];
  const seen = new Set<string>();
  for (const item of raw) {
    const tag = item.trim().toLowerCase().replace(/\s+/g, " ");
    if (!tag || seen.has(tag)) continue;
    if (tag.length > MAX_CARD_TAG_LEN) {
      throw new HubError("tag is too long", "invalid_argument", 400);
    }
    seen.add(tag);
    out.push(tag);
    if (out.length > MAX_CARD_TAGS) {
      throw new HubError("too many tags", "invalid_argument", 400);
    }
  }
  return out.length ? out : undefined;
}

export function normalizeDueOn(raw?: string): string | undefined {
  const s = raw?.trim() ?? "";
  if (!s) return undefined;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    throw new HubError("due_on must be YYYY-MM-DD", "invalid_argument", 400);
  }
  const [y, m, d] = s.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (
    dt.getUTCFullYear() !== y ||
    dt.getUTCMonth() !== m - 1 ||
    dt.getUTCDate() !== d
  ) {
    throw new HubError("due_on is not a valid date", "invalid_argument", 400);
  }
  return s;
}

export function normalizeChecklist(
  raw?: CollabChecklistItem[],
): CollabChecklistItem[] | undefined {
  if (!raw?.length) return undefined;
  const out: CollabChecklistItem[] = [];
  for (const item of raw) {
    const text = (item?.text ?? "").trim();
    if (!text) continue;
    if (text.length > MAX_CHECKLIST_TEXT) {
      throw new HubError("checklist item is too long", "invalid_argument", 400);
    }
    const id = (item.id ?? "").trim() || crypto.randomUUID();
    out.push({ id, text, done: item.done === true });
    if (out.length > MAX_CHECKLIST_ITEMS) {
      throw new HubError("too many checklist items", "invalid_argument", 400);
    }
  }
  return out.length ? out : undefined;
}

async function assertCardAssignee(
  ctx: CollabKvCtx,
  collab: Collab,
  assignedTo: string,
): Promise<void> {
  const roster = new Set(
    collab.roster.map((r) => r.address.trim().toLowerCase()),
  );
  if (roster.has(assignedTo)) return;
  for (const userId of collab.steerer_user_ids) {
    const handle = await steererHandle(ctx, userId);
    if (handle === assignedTo) return;
  }
  throw new HubError(
    "Assignee must be a collab participant",
    "invalid_argument",
    400,
  );
}

export async function indexCollabThread(
  ctx: CollabKvCtx,
  collabId: string,
  threadId: string,
): Promise<void> {
  await ctx.kv.set(ctx.collabThreadKey(collabId, threadId), threadId);
}

export async function collabNameForThread(
  ctx: CollabKvCtx,
  collabId: string | undefined,
): Promise<string | undefined> {
  if (!collabId) return undefined;
  const collab = await loadCollab(ctx, collabId);
  return collab?.name;
}
