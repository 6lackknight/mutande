import { createAuth0Verifier, createTestTokenVerifier, type TokenVerifier } from "./auth0.ts";
import {
  envelopeTooLarge,
  forbidden,
  HubError,
  notFound,
  conflict,
  quotaExceeded,
  unauthorized,
} from "./errors.ts";
import { isPlatformOpsAdmin } from "./platform_admin.ts";
import { randomToken } from "./jwt.ts";
import {
  appEnvelopeKey,
  appEnvelopesPrefix,
  assertExclusiveWireUnit,
  buildAppEnvelopeRecord,
  isEnterpriseAgentStub,
  normalizeEncryptionMode,
  openAppEnvelope,
  resolveThreadEncryptionMode,
  APP_ENVELOPE_RETENTION_MS,
} from "./app_envelope.ts";
import {
  approvePairRequest,
  assertExternalLinkVelocity,
  denyPairRequest,
  getPairingPin,
  hasApprovedExternalContact,
  issuePairingPin,
  listExternalContacts,
  listPairingOpsFlags,
  listPendingPairRequests,
  rotatePairingPin,
  submitPairRequest,
  unpairExternalContact,
  type PairingKvCtx,
} from "./external_contacts_api.ts";
import {
  approveThreadDowngrade,
  denyThreadDowngrade,
  getPendingThreadDowngrade,
  listPendingThreadDowngrades,
  messageVisibleAfterDowngrade,
  proposeThreadDowngrade,
  type DowngradeKvCtx,
} from "./thread_downgrade.ts";
import type {
  Auth0Claims,
  AuthContext,
  BlobMeta,
  Contact,
  CreateOrgInput,
  CreateThreadInput,
  Device,
  DevicePlatform,
  Draft,
  Envelope,
  Feedback,
  WaitlistEntry,
  InboxEntry,
  Invite,
  JoinOrgInput,
  MeResponse,
  Org,
  RegisterDeviceInput,
  ReplyInput,
  FetchAppMessagesInput,
  ToggleUpvoteInput,
  ToggleUpvoteResult,
  MessageUpvote,
  MessageUpvoteSummary,
  Agent,
  AgentCapabilities,
  AgentTransport,
  AgentTransportPrefs,
  AppEnvelopePayload,
  ConnectAgentInput,
  SetDefaultAgentInput,
  SetTransportDefaultInput,
  RegisterAgentInput,
  RenameAgentInput,
  RouterConfig,
  RoutingRule,
  SetRouterInput,
  ThreadFilter,
  ThreadMessage,
  ThreadMeta,
  ThreadDowngradeProposal,
  ProposeThreadDowngradeInput,
  SeedProfileInput,
  UpdateOrgInput,
  UpdateProfileInput,
  User,
  UserRole,
  PairRequest,
  PairingPinResponse,
  PairingOpsFlag,
  SubmitPairRequestInput,
  ExternalContactLink,
} from "./types.ts";
import { createBlobUrls } from "./r2.ts";
import {
  CAPABILITY_STALE_TTL_MS,
  MAX_ENVELOPE_BYTES,
  MCP_ENDPOINT_DEFAULT,
  ORG_BLOB_QUOTA_BYTES,
} from "./types.ts";
import {
  assertHandleLocal,
  assertValidAgentSlug,
  broadcastHandle,
  formatDisplayAddress,
  formatWirePath,
  isBroadcastHandle,
  isMyAgentsHandle,
  myAgentsHandle,
  parseDisplayAddress,
  parseUserHandle,
  stripAgentSuffix,
} from "./address.ts";
import { EnterpriseStore } from "./enterprise.ts";
import type { RegistryListing } from "./types.ts";

function clipRequired(value: string, field: string, max: number): string {
  const trimmed = value?.trim() ?? "";
  if (!trimmed) {
    throw new HubError(`${field} is required`, "invalid_argument", 400);
  }
  if (trimmed.length > max) {
    throw new HubError(`${field} too long (max ${max})`, "invalid_argument", 400);
  }
  return trimmed;
}

function normalizeStringList(
  values: string[],
  field: string,
  opts?: { maxItems?: number; maxLen?: number },
): string[] {
  const maxItems = opts?.maxItems ?? 20;
  const maxLen = opts?.maxLen ?? 64;
  const cleaned = values
    .map((v) => v.trim())
    .filter(Boolean)
    .map((v) => v.slice(0, maxLen));
  const unique = [...new Set(cleaned)];
  if (unique.length === 0) {
    throw new HubError(`${field} is required`, "invalid_argument", 400);
  }
  if (unique.length > maxItems) {
    throw new HubError(
      `too many ${field} (max ${maxItems})`,
      "invalid_argument",
      400,
    );
  }
  return unique;
}

function nowIso(): string {
  return new Date().toISOString();
}

function emailLocalPart(email?: string): string | null {
  if (!email) return null;
  const at = email.indexOf("@");
  if (at <= 0) return null;
  const local = email.slice(0, at).toLowerCase().replace(/[^a-z0-9._-]/g, "");
  return local || null;
}

function assertValidSlug(slug: string): void {
  if (!/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(slug)) {
    throw new HubError(
      "Org slug must be lowercase alphanumeric (hyphens allowed)",
      "invalid_slug",
    );
  }
}

function primaryRole(user: User): UserRole {
  return user.role === "org_admin" ? "org_admin" : "member";
}

function isOnboarded(user: User | null | undefined): boolean {
  return Boolean(user?.org_id && user?.handle);
}

const MAX_DISPLAY_NAME_LENGTH = 128;
/** Data-URL avatars are client-resized; keep well under Deno KV's 64KiB value limit. */
const MAX_AVATAR_URL_LENGTH = 48_000;

function assertValidAvatarUrl(value: string): void {
  if (value.length > MAX_AVATAR_URL_LENGTH) {
    throw new HubError(
      `avatar_url too large (max ${MAX_AVATAR_URL_LENGTH} chars)`,
      "invalid_argument",
      400,
    );
  }
  const isDataImage = /^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/
    .test(value);
  const isHttps = value.startsWith("https://");
  if (!isDataImage && !isHttps) {
    throw new HubError(
      "avatar_url must be an https URL or a png/jpeg/webp data URL",
      "invalid_argument",
      400,
    );
  }
}

/**
 * Fill empty profile fields from Auth0. Email may backfill anytime; name/photo
 * only before `auth0_profile_seeded_at` so mutande edits (including clears) stick.
 * Pass `seedNamePhoto: false` for claim-only email backfill (access tokens often
 * omit profile claims — web still needs a chance to seed from the ID token).
 * `forceMarkSeeded` is for the explicit POST /profile/seed path so we don't retry
 * forever when Auth0 has no name/picture.
 */
function applyAuth0ProfileSeed(
  user: User,
  seed: { email?: string; name?: string; picture?: string },
  opts: { seedNamePhoto?: boolean; forceMarkSeeded?: boolean } = {},
): boolean {
  const seedNamePhoto = opts.seedNamePhoto !== false;
  let changed = false;

  const email = seed.email?.trim();
  if (!user.email && email) {
    user.email = email;
    changed = true;
  }

  if (seedNamePhoto && !user.auth0_profile_seeded_at) {
    const name = seed.name?.trim();
    if (!user.display_name && name) {
      user.display_name = name.slice(0, MAX_DISPLAY_NAME_LENGTH);
      changed = true;
    }

    const picture = seed.picture?.trim();
    if (!user.avatar_url && picture) {
      try {
        assertValidAvatarUrl(picture);
        user.avatar_url = picture;
        changed = true;
      } catch {
        // Ignore IdP picture URLs that fail our avatar rules.
      }
    }

    if (opts.forceMarkSeeded || name || picture) {
      user.auth0_profile_seeded_at = nowIso();
      changed = true;
    }
  }

  return changed;
}

function authContextFromUser(
  user: User,
  auth0Roles: string[] = [],
): AuthContext {
  if (!isOnboarded(user)) {
    throw forbidden("Onboarding required");
  }
  return {
    userId: user.id,
    orgId: user.org_id!,
    handle: user.handle!,
    role: primaryRole(user),
    auth0Sub: user.auth0_sub,
    auth0Roles,
  };
}

function isAgentTransport(value: unknown): value is AgentTransport {
  return value === "sidecar" || value === "mcp";
}

/** Normalize legacy agent rows (pre-L1) to full hub-assigned shape. */
export function normalizeAgent(raw: Agent | Record<string, unknown>): Agent {
  const r = raw as Partial<Agent> & { id: string; user_id: string; slug: string; created_at: string };
  const transport: AgentTransport = isAgentTransport(r.transport) ? r.transport : "sidecar";
  return {
    id: r.id,
    user_id: r.user_id,
    slug: r.slug,
    created_at: r.created_at,
    transport,
    visibility: r.visibility === "public" ? "public" : "private",
    trust_tier: r.trust_tier === "enterprise" || r.trust_tier === "external"
      ? r.trust_tier
      : "org",
    billing: r.billing ?? null,
    mcp_endpoint: r.mcp_endpoint ?? (transport === "mcp" ? MCP_ENDPOINT_DEFAULT : null),
    capabilities: r.capabilities ?? null,
    capabilities_updated_at: r.capabilities_updated_at ?? null,
  };
}

/**
 * Capability freshness for UI "active now" only.
 * Staleness never blocks routing (§5.1 / §13).
 */
export function agentCapabilitiesFresh(
  agent: Agent,
  nowMs: number = Date.now(),
): boolean {
  if (!agent.capabilities_updated_at) return false;
  const t = Date.parse(agent.capabilities_updated_at);
  if (Number.isNaN(t)) return false;
  return nowMs - t < CAPABILITY_STALE_TTL_MS;
}

const HUB_ASSIGNED_CAPABILITY_FIELDS = [
  "trust_tier",
  "visibility",
  "billing",
  "transport",
  "agent_id",
  "mcp_endpoint",
] as const;

/** Strip + log client attempts to set hub-assigned fields. */
export function extractClientCapabilities(
  input: ConnectAgentInput | RegisterAgentInput | Record<string, unknown>,
): { slug: string; capabilities: AgentCapabilities; ignored: string[] } {
  const ignored: string[] = [];
  for (const field of HUB_ASSIGNED_CAPABILITY_FIELDS) {
    if (
      Object.prototype.hasOwnProperty.call(input, field) &&
      (input as Record<string, unknown>)[field] != null
    ) {
      ignored.push(field);
    }
  }
  if (ignored.length > 0) {
    console.warn(
      `[hub] ignored client-declared hub-assigned fields on agent connect: ${ignored.join(", ")}`,
    );
  }

  const slugRaw = typeof (input as { slug?: unknown }).slug === "string"
    ? (input as { slug: string }).slug
    : "";
  const slug = slugRaw.trim().toLowerCase();
  assertValidAgentSlug(slug);

  const caps: AgentCapabilities = {};
  const models = (input as ConnectAgentInput).models;
  if (Array.isArray(models) && models.length > 0) {
    caps.models = normalizeStringList(models.map(String), "models");
  }
  const modalities = (input as ConnectAgentInput).modalities;
  if (Array.isArray(modalities) && modalities.length > 0) {
    caps.modalities = normalizeStringList(modalities.map(String), "modalities");
  }
  const messageTypes = (input as ConnectAgentInput).message_types;
  if (Array.isArray(messageTypes) && messageTypes.length > 0) {
    caps.message_types = normalizeStringList(messageTypes.map(String), "message_types");
  }
  const defaultModel = (input as ConnectAgentInput).default_model;
  if (typeof defaultModel === "string" && defaultModel.trim()) {
    caps.default_model = defaultModel.trim().slice(0, 64);
  }

  return { slug, capabilities: caps, ignored };
}

/** Prefer earliest row when legacy re-registers minted the same pubkey more than once. */
function dedupeDevicesByPubkey(devices: Device[]): Device[] {
  const seen = new Set<string>();
  const out: Device[] = [];
  for (const d of devices) {
    if (seen.has(d.pubkey)) continue;
    seen.add(d.pubkey);
    out.push(d);
  }
  return out;
}

function emptyTransportPrefs(): AgentTransportPrefs {
  return { defaults: {} };
}

export class HubStore {
  readonly enterprise: EnterpriseStore;

  constructor(
    private readonly kv: Deno.Kv,
    private readonly verifier: TokenVerifier,
  ) {
    this.enterprise = new EnterpriseStore(kv);
  }
  private userKey(id: string) { return ["users", id]; }
  private auth0SubKey(sub: string) { return ["auth0_subs", sub]; }
  private handleKey(handle: string) { return ["handles", handle]; }
  private orgKey(id: string) { return ["orgs", id]; }
  private orgSlugKey(slug: string) { return ["org_slugs", slug]; }
  private memberKey(orgId: string, userId: string) { return ["org_members", orgId, userId]; }
  private membersPrefix(orgId: string) { return ["org_members", orgId]; }
  private inviteKey(code: string) { return ["invites", code]; }
  private orgInviteKey(orgId: string, code: string) { return ["org_invites", orgId, code]; }
  private orgInvitesPrefix(orgId: string) { return ["org_invites", orgId]; }
  private deviceKey(id: string) { return ["devices", id]; }
  private userDeviceKey(userId: string, deviceId: string) { return ["user_devices", userId, deviceId]; }
  private userDevicesPrefix(userId: string) { return ["user_devices", userId]; }
  /** Deterministic index so concurrent registerDevice cannot mint duplicate wraps. */
  private userPubkeyKey(userId: string, pubkey: string) {
    return ["user_pubkeys", userId, pubkey];
  }
  private threadKey(id: string) { return ["threads", id]; }
  private inboxKey(userId: string, threadId: string) { return ["inbox", userId, threadId]; }
  private inboxPrefix(userId: string) { return ["inbox", userId]; }
  private messageKey(threadId: string, messageId: string) { return ["messages", threadId, messageId]; }
  private messagesPrefix(threadId: string) { return ["messages", threadId]; }
  private appEnvelopeKey(threadId: string, messageId: string) {
    return appEnvelopeKey(threadId, messageId);
  }
  private appEnvelopesPrefix(threadId: string) {
    return appEnvelopesPrefix(threadId);
  }
  private messageUpvoteKey(threadId: string, messageId: string, agentId: string) {
    return ["message_upvotes", threadId, messageId, agentId];
  }
  private messageUpvotesPrefix(threadId: string, messageId: string) {
    return ["message_upvotes", threadId, messageId];
  }
  private draftKey(userId: string, draftId: string) { return ["drafts", userId, draftId]; }
  private draftsPrefix(userId: string) { return ["drafts", userId]; }
  private blobKey(id: string) { return ["blobs", id]; }
  private orgQuotaKey(orgId: string) { return ["org_blob_quota", orgId]; }
  private agentKey(id: string) { return ["agents", id]; }
  /** Legacy pre-L1 index: one agent_id per slug (treated as sidecar). */
  private userAgentSlugKey(userId: string, slug: string) { return ["user_agent_slugs", userId, slug]; }
  private userAgentsPrefix(userId: string) { return ["user_agent_slugs", userId]; }
  /** L1 dual-slot index: (slug, transport) → agent_id. */
  private userAgentSlotKey(userId: string, slug: string, transport: AgentTransport) {
    return ["user_agent_slugs", userId, slug, transport];
  }
  private userDefaultAgentKey(userId: string) { return ["user_default_agent", userId]; }
  private userRouterKey(userId: string) { return ["user_router", userId]; }
  private userAgentAliasKey(userId: string, slug: string) { return ["user_agent_aliases", userId, slug]; }
  private userTransportPrefsKey(userId: string) {
    return ["user_agent_transport_prefs", userId];
  }
  private feedbackKey(createdAt: string, id: string) {
    return ["feedback", createdAt, id];
  }
  private feedbackPrefix() {
    return ["feedback"];
  }
  private waitlistKey(createdAt: string, id: string) {
    return ["waitlist", createdAt, id];
  }
  private waitlistPrefix() {
    return ["waitlist"];
  }

  assertEnvelopeSize(envelope: Envelope): void {
    const size = new TextEncoder().encode(JSON.stringify(envelope)).byteLength;
    if (size > MAX_ENVELOPE_BYTES) throw envelopeTooLarge(size);
  }

  /** Shared KV/user helpers for L3 pairing module. */
  private pairingCtx(): PairingKvCtx {
    return {
      kv: this.kv,
      getUser: (id) => this.getUser(id),
      getUserByHandle: (h) => this.getUserByHandle(h),
      listDevicesForUser: async (userId) => {
        const user = await this.getUser(userId);
        if (!user || !isOnboarded(user)) return [];
        const { devices } = await this.listDevices(authContextFromUser(user));
        return devices.map((d) => ({ pubkey: d.pubkey, platform: d.platform }));
      },
      inboxKey: (u, t) => this.inboxKey(u, t),
      threadKey: (id) => this.threadKey(id),
      messageKey: (t, m) => this.messageKey(t, m),
    };
  }

  async issuePairingPin(auth: AuthContext): Promise<PairingPinResponse> {
    return issuePairingPin(this.pairingCtx(), auth);
  }

  async getPairingPin(auth: AuthContext): Promise<PairingPinResponse | null> {
    return getPairingPin(this.pairingCtx(), auth);
  }

  async rotatePairingPin(auth: AuthContext): Promise<PairingPinResponse> {
    return rotatePairingPin(this.pairingCtx(), auth);
  }

  async submitPairRequest(
    auth: AuthContext,
    input: SubmitPairRequestInput,
  ): Promise<{ request: PairRequest }> {
    return submitPairRequest(this.pairingCtx(), auth, input);
  }

  async listPendingPairRequests(
    auth: AuthContext,
  ): Promise<{ incoming: PairRequest[]; outgoing: PairRequest[] }> {
    return listPendingPairRequests(this.pairingCtx(), auth);
  }

  async approvePairRequest(
    auth: AuthContext,
    requestId: string,
  ): Promise<{ contact: Contact; thread: ThreadMeta; request: PairRequest }> {
    return approvePairRequest(this.pairingCtx(), auth, requestId);
  }

  async denyPairRequest(
    auth: AuthContext,
    requestId: string,
  ): Promise<{ ok: true }> {
    return denyPairRequest(this.pairingCtx(), auth, requestId);
  }

  async listExternalContacts(
    auth: AuthContext,
  ): Promise<{ contacts: Contact[] }> {
    return listExternalContacts(this.pairingCtx(), auth);
  }

  async unpairExternalContact(
    auth: AuthContext,
    linkId: string,
  ): Promise<{ ok: true; closed_thread_ids: string[] }> {
    return unpairExternalContact(this.pairingCtx(), auth, linkId);
  }

  async listPairingOpsFlags(
    auth: AuthContext,
  ): Promise<{ flags: PairingOpsFlag[] }> {
    if (!isPlatformOpsAdmin(auth.auth0Roles)) {
      throw forbidden("Ops admin required");
    }
    return listPairingOpsFlags(this.pairingCtx());
  }

  /** Shared helpers for L5 thread downgrade consent. */
  private downgradeCtx(): DowngradeKvCtx {
    return {
      kv: this.kv,
      getUser: (id) => this.getUser(id),
      getUserByHandle: (h) => this.getUserByHandle(h),
      getAgent: (id) => this.getAgent(id),
      listAgentsForUser: async (userId) => {
        const user = await this.getUser(userId);
        if (!user || !isOnboarded(user)) return [];
        const { agents } = await this.listAgents(authContextFromUser(user));
        return agents;
      },
      resolveAgentForUser: (userId, slug) => this.resolveAgentForUser(userId, slug),
      lookupMcpAgent: async (userId, slug) => {
        const id = await this.lookupAgentSlotId(userId, slug, "mcp");
        if (!id) return null;
        return this.getAgent(id);
      },
      getInboxEntry: (u, t) => this.getInboxEntry(u, t),
      normalizeThread: (t) => this.normalizeThread(t),
      threadVisibleToOrg: (auth, t) => this.threadVisibleToOrg(auth, t),
      threadKey: (id) => this.threadKey(id),
      messageKey: (t, m) => this.messageKey(t, m),
      messagesPrefix: (t) => this.messagesPrefix(t),
      inboxKey: (u, t) => this.inboxKey(u, t),
      appEnvelopeKey: (t, m) => this.appEnvelopeKey(t, m),
    };
  }

  async proposeThreadDowngrade(
    auth: AuthContext,
    threadId: string,
    input: ProposeThreadDowngradeInput,
  ): Promise<{ proposal: ThreadDowngradeProposal; prompt: string }> {
    return proposeThreadDowngrade(this.downgradeCtx(), auth, threadId, input);
  }

  async approveThreadDowngrade(
    auth: AuthContext,
    threadId: string,
    proposalId: string,
  ): Promise<{ proposal: ThreadDowngradeProposal; thread: ThreadMeta }> {
    return approveThreadDowngrade(this.downgradeCtx(), auth, threadId, proposalId);
  }

  async denyThreadDowngrade(
    auth: AuthContext,
    threadId: string,
    proposalId: string,
  ): Promise<{ proposal: ThreadDowngradeProposal }> {
    return denyThreadDowngrade(this.downgradeCtx(), auth, threadId, proposalId);
  }

  async listPendingThreadDowngrades(
    auth: AuthContext,
  ): Promise<{ proposals: ThreadDowngradeProposal[] }> {
    return listPendingThreadDowngrades(this.downgradeCtx(), auth);
  }

  /** @deprecated Prefer threadVisibleToOrg — kept for call-site clarity. */
  private threadAccessible(
    auth: AuthContext,
    thread: ThreadMeta,
  ): boolean {
    return this.threadVisibleToOrg(auth, thread);
  }

  async verifyAuth0Token(token: string): Promise<Auth0Claims> {
    return await this.verifier.verifyAccessToken(token);
  }

  async getUserByAuth0Sub(sub: string): Promise<User | null> {
    const mapped = await this.kv.get<string>(this.auth0SubKey(sub));
    if (!mapped.value) return null;
    return this.getUser(mapped.value);
  }

  authContextFromUser(user: User): AuthContext {
    return authContextFromUser(user);
  }

  async getMe(claims: Auth0Claims): Promise<MeResponse> {
    let user = await this.getUserByAuth0Sub(claims.sub);
    if (user) {
      // Access tokens often lack profile claims — only backfill email here.
      // Name/photo come from create/join or POST /profile/seed (web ID token).
      const seeded = applyAuth0ProfileSeed(
        user,
        { email: claims.email },
        { seedNamePhoto: false },
      );
      if (seeded) {
        await this.kv.set(this.userKey(user.id), user);
        user = (await this.getUser(user.id)) ?? user;
      }
    }
    const onboarded = isOnboarded(user);
    const org = user?.org_id ? await this.getOrg(user.org_id) : null;
    const auth0_roles = claims.roles ?? [];
    return {
      auth0_sub: claims.sub,
      email: user?.email ?? claims.email,
      onboarded,
      needs_onboarding: !onboarded,
      user: user ?? undefined,
      org: org ?? undefined,
      is_ops_admin: isPlatformOpsAdmin(auth0_roles),
      auth0_roles,
    };
  }

  /** Small profile management (web): display name, avatar, handle local part. */
  async updateProfile(
    claims: Auth0Claims,
    input: UpdateProfileInput,
  ): Promise<MeResponse> {
    const user = await this.getUserByAuth0Sub(claims.sub);
    if (!user) throw forbidden("Onboarding required");
    if (!user.org_id || !user.handle) throw forbidden("Onboarding required");

    if (input.display_name !== undefined) {
      const name = (input.display_name ?? "").trim();
      if (name.length > MAX_DISPLAY_NAME_LENGTH) {
        throw new HubError(
          `display_name too long (max ${MAX_DISPLAY_NAME_LENGTH})`,
          "invalid_argument",
          400,
        );
      }
      if (name) user.display_name = name;
      else delete user.display_name;
    }

    if (input.avatar_url !== undefined) {
      const avatar = (input.avatar_url ?? "").trim();
      if (avatar) {
        assertValidAvatarUrl(avatar);
        user.avatar_url = avatar;
      } else {
        delete user.avatar_url;
      }
    }

    let rename: { oldHandle: string; newHandle: string } | undefined;
    if (input.handle !== undefined) {
      const raw = (input.handle ?? "").trim();
      if (!raw) {
        throw new HubError("handle is required", "invalid_argument", 400);
      }
      const org = await this.getOrg(user.org_id);
      if (!org) throw notFound("Org");
      const parsed = raw.includes("@")
        ? parseUserHandle(raw)
        : { local: raw, orgSlug: org.slug };
      const local = parsed.local.trim().toLowerCase();
      assertHandleLocal(local);
      if (parsed.orgSlug.toLowerCase() !== org.slug) {
        throw forbidden("Handle must stay in your org");
      }
      const newHandle = `${local}@${org.slug}`;
      if (newHandle !== user.handle) {
        rename = { oldHandle: user.handle, newHandle };
        user.handle = newHandle;
      }
    }

    // Explicit mutande edit — don't let later Auth0 seed refill clears.
    if (!user.auth0_profile_seeded_at) {
      user.auth0_profile_seeded_at = nowIso();
    }

    if (rename) {
      const userRes = await this.kv.get(this.userKey(user.id));
      const oldRes = await this.kv.get(this.handleKey(rename.oldHandle));
      const newRes = await this.kv.get(this.handleKey(rename.newHandle));
      if (newRes.value && newRes.value !== user.id) {
        throw conflict("Handle already registered");
      }
      const tx = this.kv.atomic();
      tx.check(userRes).check(oldRes).check(newRes);
      tx.set(this.userKey(user.id), user);
      if (rename.oldHandle !== rename.newHandle) {
        tx.delete(this.handleKey(rename.oldHandle));
      }
      tx.set(this.handleKey(rename.newHandle), user.id);
      const res = await tx.commit();
      if (!res.ok) throw conflict("Handle update conflict");
    } else {
      await this.kv.set(this.userKey(user.id), user);
    }
    return this.getMe(claims);
  }

  /**
   * One-shot Auth0 → mutande profile seed (web ID-token session or token claims).
   * Never overwrites existing name/photo/email; name/photo only before first seed.
   */
  async seedProfile(
    claims: Auth0Claims,
    input: SeedProfileInput = {},
  ): Promise<MeResponse> {
    const user = await this.getUserByAuth0Sub(claims.sub);
    if (!user) throw forbidden("Onboarding required");

    const changed = applyAuth0ProfileSeed(
      user,
      {
        email: input.email?.trim() || claims.email,
        name: input.display_name?.trim() || claims.name,
        picture: input.avatar_url?.trim() || claims.picture,
      },
      { forceMarkSeeded: true },
    );
    if (changed) {
      await this.kv.set(this.userKey(user.id), user);
    }
    return this.getMe(claims);
  }

  async verifyAuth0Claims(token: string): Promise<Auth0Claims> {
    return this.verifyAuth0Token(token);
  }

  async verifyAccessToken(token: string): Promise<AuthContext> {
    const claims = await this.verifyAuth0Token(token);
    const user = await this.getUserByAuth0Sub(claims.sub);
    if (!isOnboarded(user)) {
      throw forbidden("Onboarding required");
    }
    return authContextFromUser(user!, claims.roles ?? []);
  }

  async createOrgWithAdmin(
    claims: Auth0Claims,
    input: CreateOrgInput,
  ): Promise<{ org: Org; user: User }> {
    const slug = input.slug.trim().toLowerCase();
    assertValidSlug(slug);
    await this.enterprise.assertOrgSlugAvailable(slug);
    const name = (input.name?.trim() || slug);

    if (await this.getUserByAuth0Sub(claims.sub)) {
      throw conflict("User already onboarded");
    }

    const local = (input.handle
      ? parseUserHandle(input.handle.includes("@") ? input.handle : `${input.handle}@${slug}`).local
      : (emailLocalPart(claims.email) ?? "admin")).trim().toLowerCase();
    assertHandleLocal(local);
    const handle = `${local}@${slug}`;

    const slugRes = await this.kv.get(this.orgSlugKey(slug));
    if (slugRes.value) throw conflict(`Org slug '${slug}' already exists`);
    const handleRes = await this.kv.get(this.handleKey(handle));
    if (handleRes.value) throw conflict("Handle already registered");

    const org: Org = { id: crypto.randomUUID(), slug, name, created_at: nowIso() };
    const user: User = {
      id: crypto.randomUUID(),
      auth0_sub: claims.sub,
      handle,
      org_id: org.id,
      role: "org_admin",
      email: claims.email,
      created_at: nowIso(),
    };
    applyAuth0ProfileSeed(user, {
      email: claims.email,
      name: claims.name,
      picture: claims.picture,
    });

    const subRes = await this.kv.get(this.auth0SubKey(claims.sub));
    const tx = this.kv.atomic();
    tx.check(slugRes).check(handleRes).check(subRes);
    tx.set(this.orgKey(org.id), org);
    tx.set(this.orgSlugKey(slug), org);
    tx.set(this.orgQuotaKey(org.id), 0);
    tx.set(this.userKey(user.id), user);
    tx.set(this.auth0SubKey(claims.sub), user.id);
    tx.set(this.handleKey(handle), user.id);
    tx.set(this.memberKey(org.id, user.id), user.id);
    const res = await tx.commit();
    if (!res.ok) throw conflict("Org create conflict");
    return { org, user };
  }

  async joinOrg(
    claims: Auth0Claims,
    input: JoinOrgInput,
  ): Promise<{ org: Org; user: User }> {
    if (await this.getUserByAuth0Sub(claims.sub)) {
      throw conflict("User already onboarded");
    }

    const inviteRes = await this.kv.get<Invite>(this.inviteKey(input.invite_code));
    const invite = inviteRes.value;
    if (!invite) throw notFound("Invite");
    if (invite.used_by) throw conflict("Invite already used");

    const org = await this.getOrg(invite.org_id);
    if (!org) throw notFound("Org");

    let handle: string;
    if (input.handle) {
      const raw = input.handle.includes("@") ? input.handle : `${input.handle}@${org.slug}`;
      const { local, orgSlug } = parseUserHandle(raw);
      const normalized = local.trim().toLowerCase();
      assertHandleLocal(normalized);
      if (orgSlug.toLowerCase() !== org.slug) throw forbidden("Handle must belong to invite org");
      handle = `${normalized}@${org.slug}`;
    } else {
      const local = emailLocalPart(claims.email) ?? "user";
      assertHandleLocal(local);
      handle = `${local}@${org.slug}`;
    }

    const handleRes = await this.kv.get(this.handleKey(handle));
    if (handleRes.value) throw conflict("Handle already registered");

    const user: User = {
      id: crypto.randomUUID(),
      auth0_sub: claims.sub,
      handle,
      org_id: org.id,
      role: "member",
      email: claims.email,
      created_at: nowIso(),
    };
    applyAuth0ProfileSeed(user, {
      email: claims.email,
      name: claims.name,
      picture: claims.picture,
    });

    const subRes = await this.kv.get(this.auth0SubKey(claims.sub));
    const tx = this.kv.atomic();
    tx.check(inviteRes).check(handleRes).check(subRes);
    tx.set(this.userKey(user.id), user);
    tx.set(this.auth0SubKey(claims.sub), user.id);
    tx.set(this.handleKey(handle), user.id);
    tx.set(this.memberKey(org.id, user.id), user.id);
    tx.set(this.inviteKey(invite.code), { ...invite, used_by: user.id });
    tx.delete(this.orgInviteKey(org.id, invite.code));
    const res = await tx.commit();
    if (!res.ok) throw conflict("Join conflict");
    return { org, user };
  }

  async registerDevice(auth: AuthContext, input: RegisterDeviceInput): Promise<Device> {
    if (!input.pubkey?.trim()) throw new HubError("pubkey is required", "invalid_pubkey");
    if (!["macos", "ios", "web"].includes(input.platform)) {
      throw new HubError("platform must be macos, ios, or web", "invalid_platform");
    }
    if (input.agent_slug?.trim()) {
      await this.registerAgent(auth, { slug: input.agent_slug.trim() });
    }
    const pubkey = input.pubkey.trim();
    const pubkeyIndex = this.userPubkeyKey(auth.userId, pubkey);

    // Collapse pre-index duplicates so contacts never expose the same pubkey N times.
    await this.purgeDuplicateDevices(auth);

    const returnOrUpdate = async (existing: Device): Promise<Device> => {
      if (existing.platform === input.platform) return existing;
      const updated: Device = { ...existing, platform: input.platform };
      await this.kv.set(this.deviceKey(existing.id), updated);
      return updated;
    };

    // Fast path: atomic pubkey index.
    const idxRes = await this.kv.get<string>(pubkeyIndex);
    if (idxRes.value) {
      const existing = await this.kv.get<Device>(this.deviceKey(idxRes.value));
      if (existing.value) return await returnOrUpdate(existing.value);
    }

    // Legacy devices registered before the pubkey index existed.
    const devices = await this.fetchDevices(auth);
    const legacy = devices.find((d) => d.pubkey === pubkey);
    if (legacy) {
      await this.kv.set(pubkeyIndex, legacy.id);
      return await returnOrUpdate(legacy);
    }

    const device: Device = {
      id: crypto.randomUUID(),
      user_id: auth.userId,
      pubkey,
      platform: input.platform,
      created_at: nowIso(),
    };
    const tx = this.kv.atomic();
    tx.check(idxRes);
    tx.set(this.deviceKey(device.id), device);
    tx.set(this.userDeviceKey(auth.userId, device.id), device.id);
    tx.set(pubkeyIndex, device.id);
    const res = await tx.commit();
    if (!res.ok) {
      // Lost a race — return the winner.
      const again = await this.kv.get<string>(pubkeyIndex);
      if (again.value) {
        const winner = await this.kv.get<Device>(this.deviceKey(again.value));
        if (winner.value) return await returnOrUpdate(winner.value);
      }
      throw conflict("Device register conflict");
    }
    return device;
  }

  /** All device rows for a user (may include legacy same-pubkey duplicates). */
  private async fetchDevices(auth: AuthContext): Promise<Device[]> {
    const devices: Device[] = [];
    const iter = this.kv.list<string>({ prefix: this.userDevicesPrefix(auth.userId) });
    for await (const entry of iter) {
      const device = await this.kv.get<Device>(this.deviceKey(entry.value));
      if (device.value) devices.push(device.value);
    }
    devices.sort((a, b) => a.created_at.localeCompare(b.created_at));
    return devices;
  }

  /**
   * Keep earliest device per pubkey; delete later duplicates and refresh pubkey index.
   * Pre-index re-registers left multiple rows with the same key — that breaks seal.
   */
  private async purgeDuplicateDevices(auth: AuthContext): Promise<void> {
    const devices = await this.fetchDevices(auth);
    const keepByPubkey = new Map<string, Device>();
    const remove: Device[] = [];
    for (const d of devices) {
      const existing = keepByPubkey.get(d.pubkey);
      if (!existing) {
        keepByPubkey.set(d.pubkey, d);
      } else {
        remove.push(d);
      }
    }
    for (const d of remove) {
      await this.kv.delete(this.deviceKey(d.id));
      await this.kv.delete(this.userDeviceKey(auth.userId, d.id));
    }
    for (const [pubkey, d] of keepByPubkey) {
      await this.kv.set(this.userPubkeyKey(auth.userId, pubkey), d.id);
    }
  }

  async listDevices(auth: AuthContext): Promise<{ devices: Device[] }> {
    const devices = await this.fetchDevices(auth);
    return { devices: dedupeDevicesByPubkey(devices) };
  }

  async registerAgent(auth: AuthContext, input: RegisterAgentInput): Promise<Agent> {
    // Legacy register path = sidecar connect without capability refresh extras.
    return this.connectAgent(auth, "sidecar", input);
  }

  /**
   * Store helper for MCP connect (same as route POST /v1/agents/connect/mcp).
   * Hub assigns transport — never from the request body (§5.2).
   */
  async registerWebAgent(
    auth: AuthContext,
    input: ConnectAgentInput | RegisterAgentInput,
  ): Promise<Agent> {
    return this.connectAgent(auth, "mcp", input);
  }

  /**
   * Capability handshake / slot upsert.
   * `transport` is hub-assigned from the authenticated connection route — never from the body.
   */
  async connectAgent(
    auth: AuthContext,
    transport: AgentTransport,
    input: ConnectAgentInput | RegisterAgentInput,
  ): Promise<Agent> {
    const { slug, capabilities } = extractClientCapabilities(input);
    const now = nowIso();
    const existingId = await this.lookupAgentSlotId(auth.userId, slug, transport);
    if (existingId) {
      const existing = await this.getAgent(existingId);
      if (existing) {
        const updated: Agent = {
          ...existing,
          transport,
          visibility: existing.visibility ?? "private",
          trust_tier: existing.trust_tier ?? "org",
          billing: null, // L4 — never accept from client
          mcp_endpoint: transport === "mcp"
            ? (Deno.env.get("MCP_ENDPOINT")?.trim().replace(/\/+$/, "") || MCP_ENDPOINT_DEFAULT)
            : null,
          capabilities: Object.keys(capabilities).length > 0
            ? capabilities
            : existing.capabilities,
          capabilities_updated_at: now,
        };
        await this.kv.set(this.agentKey(updated.id), updated);
        await this.ensureSlotIndex(auth.userId, updated);
        return updated;
      }
    }

    const agent: Agent = {
      id: crypto.randomUUID(),
      user_id: auth.userId,
      slug,
      created_at: now,
      transport,
      visibility: "private",
      trust_tier: "org",
      billing: null,
      mcp_endpoint: transport === "mcp"
        ? (Deno.env.get("MCP_ENDPOINT")?.trim().replace(/\/+$/, "") || MCP_ENDPOINT_DEFAULT)
        : null,
      capabilities: Object.keys(capabilities).length > 0 ? capabilities : null,
      capabilities_updated_at: now,
    };

    const router = await this.loadRouter(auth.userId);
    const prefs = await this.loadTransportPrefs(auth.userId);
    const preferred = prefs.defaults[slug] ?? "sidecar";
    // Only own the router rule when this slot matches preferred transport, or no rule yet.
    const existingRule = router.rules.find((r) => r.match_slug === slug);
    let rules = [...router.rules];
    if (!existingRule || preferred === transport) {
      rules = rules.filter((r) => r.match_slug !== slug);
      rules.push({ match_slug: slug, agent_id: agent.id });
      rules.sort((a, b) => a.match_slug.localeCompare(b.match_slug));
    }
    const defaultAgentId = router.default_agent_id ?? agent.id;

    const tx = this.kv.atomic();
    tx.set(this.agentKey(agent.id), agent);
    tx.set(this.userAgentSlotKey(auth.userId, slug, transport), agent.id);
    // Keep legacy sidecar pointer for older readers / migration.
    if (transport === "sidecar") {
      tx.set(this.userAgentSlugKey(auth.userId, slug), agent.id);
    }
    tx.set(this.userDefaultAgentKey(auth.userId), defaultAgentId);
    tx.set(this.userRouterKey(auth.userId), {
      default_agent_id: defaultAgentId,
      rules,
    } satisfies RouterConfig);
    const res = await tx.commit();
    if (!res.ok) throw conflict("Agent register conflict");
    return agent;
  }

  async addAgent(auth: AuthContext, input: RegisterAgentInput): Promise<Agent> {
    return this.registerAgent(auth, input);
  }

  async listAgents(auth: AuthContext): Promise<{ agents: Agent[]; default_agent_id: string | null }> {
    const byId = new Map<string, Agent>();
    const iter = this.kv.list<string>({ prefix: this.userAgentsPrefix(auth.userId) });
    for await (const entry of iter) {
      const agent = await this.getAgent(entry.value);
      if (agent) byId.set(agent.id, agent);
    }
    const agents = [...byId.values()].sort((a, b) => {
      const slugCmp = a.slug.localeCompare(b.slug);
      if (slugCmp !== 0) return slugCmp;
      return a.transport.localeCompare(b.transport);
    });
    const router = await this.loadRouter(auth.userId);
    return { agents, default_agent_id: router.default_agent_id };
  }

  async listAgentsForHandle(
    auth: AuthContext,
    handle: string,
  ): Promise<{
    agents: Agent[];
    default_agent_id: string | null;
    /** Per-slug preferred transport — needed so clients can mirror hub bare-slug resolve. */
    transport_defaults: Record<string, AgentTransport>;
  }> {
    const bare = stripAgentSuffix(handle.trim());
    await this.assertSameOrgHandle(auth.orgId, bare);
    const user = await this.getUserByHandle(bare);
    if (!user) throw notFound("User");
    const ctx = authContextFromUser(user);
    const { agents, default_agent_id } = await this.listAgents(ctx);
    const prefs = await this.loadTransportPrefs(user.id);
    return {
      agents,
      default_agent_id,
      transport_defaults: prefs.defaults,
    };
  }

  async getTransportPrefs(auth: AuthContext): Promise<AgentTransportPrefs> {
    return this.loadTransportPrefs(auth.userId);
  }

  /**
   * Settings: preferred transport per display slug for bare-slug resolution.
   * Updates router rule to the preferred slot when that slot exists.
   */
  async setTransportDefault(
    auth: AuthContext,
    input: SetTransportDefaultInput,
  ): Promise<AgentTransportPrefs> {
    const slug = input.slug.trim().toLowerCase();
    assertValidAgentSlug(slug);
    if (!isAgentTransport(input.transport)) {
      throw new HubError("transport must be sidecar or mcp", "invalid_argument", 400);
    }
    const prefs = await this.loadTransportPrefs(auth.userId);
    prefs.defaults[slug] = input.transport;

    const slotId = await this.lookupAgentSlotId(auth.userId, slug, input.transport);
    const router = await this.loadRouter(auth.userId);
    let rules = [...router.rules];
    if (slotId) {
      rules = rules.filter((r) => r.match_slug !== slug);
      rules.push({ match_slug: slug, agent_id: slotId });
      rules.sort((a, b) => a.match_slug.localeCompare(b.match_slug));
    }

    const tx = this.kv.atomic();
    tx.set(this.userTransportPrefsKey(auth.userId), prefs);
    if (slotId) {
      tx.set(this.userRouterKey(auth.userId), {
        default_agent_id: router.default_agent_id,
        rules,
      } satisfies RouterConfig);
    }
    const res = await tx.commit();
    if (!res.ok) throw conflict("Transport preference update conflict");
    return prefs;
  }

  async getRouter(auth: AuthContext): Promise<RouterConfig> {
    return this.loadRouter(auth.userId);
  }

  async setRouter(auth: AuthContext, input: SetRouterInput): Promise<RouterConfig> {
    const current = await this.loadRouter(auth.userId);
    let defaultAgentId = current.default_agent_id;
    if (input.default_agent_id !== undefined) {
      if (input.default_agent_id === null) {
        defaultAgentId = null;
      } else {
        const agent = await this.getAgent(input.default_agent_id);
        if (!agent || agent.user_id !== auth.userId) throw notFound("Agent");
        defaultAgentId = agent.id;
      }
    }

    let rules = current.rules;
    if (input.rules !== undefined) {
      rules = await this.normalizeRules(auth.userId, input.rules);
    }

    const router: RouterConfig = { default_agent_id: defaultAgentId, rules };
    const tx = this.kv.atomic();
    if (defaultAgentId) {
      tx.set(this.userDefaultAgentKey(auth.userId), defaultAgentId);
    } else {
      tx.delete(this.userDefaultAgentKey(auth.userId));
    }
    tx.set(this.userRouterKey(auth.userId), router);
    const res = await tx.commit();
    if (!res.ok) throw conflict("Router update conflict");
    return router;
  }

  async setDefaultAgent(auth: AuthContext, input: SetDefaultAgentInput): Promise<Agent> {
    const agent = await this.getAgent(input.agent_id);
    if (!agent || agent.user_id !== auth.userId) throw notFound("Agent");
    await this.setRouter(auth, { default_agent_id: agent.id });
    return agent;
  }

  async renameAgent(auth: AuthContext, agentId: string, input: RenameAgentInput): Promise<Agent> {
    const newSlug = input.slug.trim().toLowerCase();
    assertValidAgentSlug(newSlug);
    const agent = await this.getAgent(agentId);
    if (!agent || agent.user_id !== auth.userId) throw notFound("Agent");
    if (agent.slug === newSlug) return agent;

    const transport = agent.transport;
    const takenId = await this.lookupAgentSlotId(auth.userId, newSlug, transport);
    if (takenId && takenId !== agentId) {
      throw conflict("Agent slug already taken for this transport");
    }

    const oldSlug = agent.slug;
    const updated: Agent = { ...agent, slug: newSlug };
    const router = await this.loadRouter(auth.userId);
    const rules = router.rules.map((r) =>
      r.agent_id === agentId && r.match_slug === oldSlug
        ? { ...r, match_slug: newSlug }
        : r
    );
    if (!rules.some((r) => r.agent_id === agentId && r.match_slug === newSlug)) {
      rules.push({ match_slug: newSlug, agent_id: agentId });
    }
    rules.sort((a, b) => a.match_slug.localeCompare(b.match_slug));

    const prefs = await this.loadTransportPrefs(auth.userId);
    if (prefs.defaults[oldSlug] && !prefs.defaults[newSlug]) {
      prefs.defaults[newSlug] = prefs.defaults[oldSlug]!;
      delete prefs.defaults[oldSlug];
    }

    const legacyOld = await this.kv.get<string>(this.userAgentSlugKey(auth.userId, oldSlug));
    const otherAtOld = await this.lookupAgentSlotId(
      auth.userId,
      oldSlug,
      transport === "sidecar" ? "mcp" : "sidecar",
    );

    const tx = this.kv.atomic();
    tx.delete(this.userAgentSlotKey(auth.userId, oldSlug, transport));
    tx.set(this.userAgentSlotKey(auth.userId, newSlug, transport), agent.id);
    if (transport === "sidecar") {
      tx.set(this.userAgentSlugKey(auth.userId, newSlug), agent.id);
    }
    if (legacyOld.value === agentId && !otherAtOld) {
      tx.delete(this.userAgentSlugKey(auth.userId, oldSlug));
    }
    tx.set(this.agentKey(agent.id), updated);
    tx.set(this.userAgentAliasKey(auth.userId, oldSlug), {
      agent_id: agentId,
      current_slug: newSlug,
    });
    tx.delete(this.userAgentAliasKey(auth.userId, newSlug));
    tx.set(this.userRouterKey(auth.userId), {
      default_agent_id: router.default_agent_id,
      rules,
    } satisfies RouterConfig);
    tx.set(this.userTransportPrefsKey(auth.userId), prefs);
    const res = await tx.commit();
    if (!res.ok) throw conflict("Agent rename conflict");
    return updated;
  }

  async createInvite(
    auth: AuthContext,
    opts?: { email?: string },
  ): Promise<Invite> {
    if (auth.role !== "org_admin") throw forbidden("Org admin required");
    const org = await this.getOrg(auth.orgId);
    if (!org) throw notFound("Org");
    const email = opts?.email?.trim().toLowerCase() || undefined;
    const invite: Invite = {
      code: randomToken(),
      org_id: auth.orgId,
      created_by: auth.userId,
      created_at: nowIso(),
      ...(email ? { email } : {}),
    };
    await this.kv.set(this.inviteKey(invite.code), invite);
    await this.kv.set(this.orgInviteKey(auth.orgId, invite.code), invite.code);
    return invite;
  }

  async listInvites(auth: AuthContext): Promise<{ invites: Invite[] }> {
    if (auth.role !== "org_admin") throw forbidden("Org admin required");
    const invites: Invite[] = [];
    const iter = this.kv.list<string>({ prefix: this.orgInvitesPrefix(auth.orgId) });
    for await (const entry of iter) {
      const invite = await this.kv.get<Invite>(this.inviteKey(entry.value));
      if (invite.value && !invite.value.used_by) invites.push(invite.value);
    }
    invites.sort((a, b) => b.created_at.localeCompare(a.created_at));
    return { invites };
  }

  async listContacts(auth: AuthContext): Promise<{ contacts: Contact[] }> {
    const org = await this.getOrg(auth.orgId);
    if (!org) throw notFound("Org");

    const contacts: Contact[] = [{
      handle: broadcastHandle(org.slug),
      pubkey: null,
      devices: [],
      kind: "broadcast",
    }];
    const iter = this.kv.list<string>({ prefix: this.membersPrefix(auth.orgId) });
    for await (const entry of iter) {
      const memberId = entry.value;
      if (memberId === auth.userId) continue;
      const user = await this.getUser(memberId);
      if (!user || !isOnboarded(user)) continue;
      const { devices } = await this.listDevices(authContextFromUser(user));
      // listDevices already collapses same-pubkey legacy dupes — one wrap target each.
      const mapped = devices.map((d) => ({ pubkey: d.pubkey, platform: d.platform }));
      contacts.push({
        handle: user.handle!,
        pubkey: mapped[0]?.pubkey ?? user.pubkey ?? null,
        devices: mapped,
        kind: "org",
      });
    }
    contacts.sort((a, b) => a.handle.localeCompare(b.handle));
    return { contacts };
  }

  async createThread(auth: AuthContext, input: CreateThreadInput): Promise<{
    thread: ThreadMeta;
    message_id: string;
  }> {
    const wireKind = assertExclusiveWireUnit(input);
    if (wireKind === "e2e") {
      this.assertEnvelopeSize(input.envelope!);
    }

    const sender = await this.getUser(auth.userId);
    if (!sender?.handle) throw notFound("User");

    const org = await this.getOrg(auth.orgId);
    if (!org) throw notFound("Org");

    const senderParts = parseUserHandle(sender.handle);
    const fromAgent = await this.resolveSenderAgent(auth.userId, {
      from_agent_id: input.from_agent_id,
      from_agent: input.from_agent,
    });
    const fromDisplay = formatDisplayAddress(senderParts.local, senderParts.orgSlug, fromAgent.slug);

    const trimmedTo = input.to.trim();
    const isOrgBroadcast =
      isBroadcastHandle(trimmedTo) && trimmedTo === broadcastHandle(org.slug);
    const isMyAgents = isMyAgentsHandle(trimmedTo);
    let recipientIds: string[] = [];
    let audience = trimmedTo;
    let audienceAgentId: string | undefined;
    let audienceWirePath: string | undefined;
    let isBroadcast = false;
    let audienceAgent: Agent | null = null;
    let extraParticipants: Agent[] = [];
    let hasExternalContact = false;
    let activeExternalLinkId: string | undefined;
    let enterpriseListing: RegistryListing | null = null;

    // Enterprise listing agents cannot start new outbound threads (§7.3 / §12).
    await this.enterprise.assertEnterpriseAgentSend(fromAgent.id, {
      is_new_thread: true,
    });

    if (isOrgBroadcast) {
      // Exclude sender when other members exist; sole-member orgs deliver @all@org to self
      // (default-agent inbox) so founders can still use broadcast before inviting anyone.
      recipientIds = await this.listMemberIds(auth.orgId, auth.userId);
      if (recipientIds.length === 0) {
        recipientIds = [auth.userId];
      }
      audience = broadcastHandle(org.slug);
      isBroadcast = true;
      // Mode from each member's default agent (§4.2 rule 6 — single broadcast thread today).
      for (const rid of recipientIds) {
        try {
          const a = await this.resolveAgentForUser(rid);
          extraParticipants.push(a);
        } catch {
          // Member with no agents — ignore for mode.
        }
      }
    } else if (isMyAgents) {
      // Bare @all → one shared my-agents group thread (inbox for this user).
      const { agents } = await this.listAgents(auth);
      if (agents.length === 0) {
        throw new HubError("No agents registered", "unknown_agent", 400);
      }
      recipientIds = [auth.userId];
      audience = myAgentsHandle();
      isBroadcast = true;
      extraParticipants = agents;
    } else {
      const parsedTo = parseDisplayAddress(trimmedTo);

      if (parsedTo.kind === "self_agent") {
        // @claude → expand to you@org/claude for the authenticated user.
        const toAgent = await this.resolveAgentForUser(auth.userId, parsedTo.agentSlug);
        audience = formatDisplayAddress(senderParts.local, senderParts.orgSlug, toAgent.slug);
        audienceAgentId = toAgent.id;
        audienceWirePath = formatWirePath(senderParts.orgSlug, senderParts.local, toAgent.slug);
        audienceAgent = toAgent;
        if (fromAgent.id === toAgent.id) {
          throw new HubError(
            `Cannot hand off to the same agent (${fromAgent.slug}). Send to a different agent address, e.g. @claude`,
            "invalid_recipient",
          );
        }
        recipientIds = [auth.userId];
      } else if (parsedTo.kind === "user") {
        const bareTo = formatDisplayAddress(parsedTo.local, parsedTo.orgSlug);
        // L4: public enterprise address — billing gate, no contact/same-org required.
        if (!parsedTo.agentSlug) {
          enterpriseListing = await this.enterprise.resolvePublishedEnterprise(
            bareTo,
          );
        }
        if (enterpriseListing) {
          const entAgent = await this.getAgent(enterpriseListing.agent_id);
          if (!entAgent) throw notFound("Enterprise agent");
          audience = enterpriseListing.address;
          audienceAgentId = entAgent.id;
          audienceAgent = entAgent;
          recipientIds = [enterpriseListing.submitter_user_id];
        } else {
          const sameOrg = parsedTo.orgSlug === org.slug;
          let externalLink: ExternalContactLink | null = null;
          if (!sameOrg) {
            externalLink = await hasApprovedExternalContact(
              this.pairingCtx(),
              auth.userId,
              bareTo,
            );
            if (!externalLink) {
              throw forbidden(
                "Cross-org mail requires an approved external contact",
              );
            }
            hasExternalContact = true;
            await assertExternalLinkVelocity(
              this.pairingCtx(),
              externalLink.id,
            );
            activeExternalLinkId = externalLink.id;
          } else {
            await this.assertSameOrgHandle(auth.orgId, bareTo);
          }
          const recipient = await this.getUserByHandle(bareTo);
          if (!recipient) throw notFound("Recipient");

          const toAgent = await this.resolveAgentForUser(recipient.id, parsedTo.agentSlug);
          audience = formatDisplayAddress(parsedTo.local, parsedTo.orgSlug, toAgent.slug);
          audienceAgentId = toAgent.id;
          audienceWirePath = formatWirePath(parsedTo.orgSlug, parsedTo.local, toAgent.slug);
          audienceAgent = toAgent;

          if (recipient.id === auth.userId) {
            // Self-handoff: bare → default agent; /agent → that slot. Reject same-agent noops.
            if (fromAgent.id === toAgent.id) {
              throw new HubError(
                `Cannot hand off to the same agent (${fromAgent.slug}). Send to a different agent address, e.g. ${senderParts.local}@${senderParts.orgSlug}/claude or @claude`,
                "invalid_recipient",
              );
            }
          }
          recipientIds = [recipient.id];
        }
      } else {
        throw new HubError("Invalid recipient address", "invalid_handle");
      }
    }

    const encryptionMode = resolveThreadEncryptionMode({
      sender: fromAgent,
      audience: audienceAgent,
      extraParticipants,
      hasExternalContact,
      hasEnterpriseAgent: Boolean(enterpriseListing) ||
        isEnterpriseAgentStub(audienceAgent) ||
        extraParticipants.some((a) => isEnterpriseAgentStub(a)),
    });
    // Wire unit must match resolved mode — never mix stores (§4.2.1).
    if (encryptionMode === "e2e" && wireKind !== "e2e") {
      throw new HubError(
        "E2E threads require envelope (not app_envelope)",
        "invalid_argument",
        400,
      );
    }
    if (encryptionMode === "app_envelope" && wireKind !== "app_envelope") {
      throw new HubError(
        "app_envelope threads require app_envelope payload (not E2E envelope)",
        "invalid_argument",
        400,
      );
    }
    // Web slots can only start non-E2E threads (§4.2 rule 2) — enforced via mode + wire check.

    const threadId = crypto.randomUUID();
    const messageId = crypto.randomUUID();
    const ts = nowIso();

    const payloadBytes = encryptionMode === "app_envelope"
      ? new TextEncoder().encode(JSON.stringify(input.app_envelope)).byteLength
      : 0;

    // L4 debit-on-store: plan before commit so insufficient balance stores nothing.
    let enterpriseDebit: Awaited<
      ReturnType<EnterpriseStore["planEnterpriseDebit"]>
    > | null = null;
    if (enterpriseListing) {
      enterpriseDebit = await this.enterprise.planEnterpriseDebit(auth, {
        listing_id: enterpriseListing.id,
        thread_id: threadId,
        payload_bytes: payloadBytes,
        blob_count: 0,
      });
    }

    const thread: ThreadMeta = {
      id: threadId,
      kind: isBroadcast ? "broadcast" : "direct",
      status: "open",
      from: fromDisplay,
      from_user_id: sender.id,
      from_agent_id: fromAgent.id,
      audience,
      audience_agent_id: audienceAgentId,
      audience_wire_path: audienceWirePath,
      org_id: auth.orgId,
      participant_count: isBroadcast ? recipientIds.length + 1 : 2,
      reply_count: 0,
      encryption_mode: encryptionMode,
      ...(enterpriseListing
        ? { enterprise_listing_id: enterpriseListing.id }
        : {}),
      ...(activeExternalLinkId
        ? {
          external_link_id: activeExternalLinkId,
          participant_user_ids: [
            sender.id,
            ...recipientIds.filter((id) => id !== sender.id),
          ],
        }
        : {}),
      created_at: ts,
      updated_at: ts,
    };

    const message: ThreadMessage = {
      id: messageId,
      thread_id: threadId,
      from_user_id: sender.id,
      from_handle: fromDisplay,
      from_agent_id: fromAgent.id,
      content_store: encryptionMode,
      created_at: ts,
      ...(encryptionMode === "e2e" ? { envelope: input.envelope! } : {}),
    };

    for (let attempt = 0; attempt < 8; attempt++) {
      if (attempt > 0 && enterpriseListing) {
        enterpriseDebit = await this.enterprise.planEnterpriseDebit(auth, {
          listing_id: enterpriseListing.id,
          thread_id: threadId,
          payload_bytes: payloadBytes,
          blob_count: 0,
        });
      }

      const tx = this.kv.atomic();
      tx.set(this.threadKey(threadId), thread);
      tx.set(this.messageKey(threadId, messageId), message);

      if (encryptionMode === "app_envelope") {
        const record = await buildAppEnvelopeRecord({
          threadId,
          messageId,
          fromUserId: sender.id,
          fromAgentId: fromAgent.id,
          createdAt: ts,
          payload: this.normalizeAppPayload(input.app_envelope!),
        });
        tx.set(this.appEnvelopeKey(threadId, messageId), record, {
          expireIn: APP_ENVELOPE_RETENTION_MS,
        });
      }

      if (enterpriseDebit) {
        enterpriseDebit.apply(tx);
      }

      // Self-collab (own agent / bare @all / sole-member @all@org): recipientIds
      // includes the sender. One inbox key per user — keep Waiting (replied) and
      // role=recipient so own agents can still reply. Do not clobber to pending.
      const selfDelivery = recipientIds.includes(sender.id);
      tx.set(this.inboxKey(sender.id, threadId), {
        thread_id: threadId,
        your_status: "replied",
        role: selfDelivery ? "recipient" : "sender",
        updated_at: ts,
      } satisfies InboxEntry);

      for (const rid of recipientIds) {
        if (rid === sender.id) continue;
        tx.set(this.inboxKey(rid, threadId), {
          thread_id: threadId,
          your_status: "pending",
          role: "recipient",
          updated_at: ts,
        } satisfies InboxEntry);
      }

      const res = await tx.commit();
      if (res.ok) {
        return { thread, message_id: messageId };
      }
    }
    throw new HubError("Failed to create thread", "internal", 500);
  }

  async listThreads(
    auth: AuthContext,
    filter?: ThreadFilter,
  ): Promise<{ threads: ThreadMeta[] }> {
    const threads: ThreadMeta[] = [];
    const iter = this.kv.list<InboxEntry>({ prefix: this.inboxPrefix(auth.userId) });

    for await (const entry of iter) {
      const inbox = entry.value;
      const threadRes = await this.kv.get<ThreadMeta>(this.threadKey(inbox.thread_id));
      const thread = threadRes.value ? this.normalizeThread(threadRes.value) : null;
      if (!thread || !this.threadVisibleToOrg(auth, thread)) continue;

      const enriched: ThreadMeta = {
        ...thread,
        your_status: this.effectiveYourStatus(auth, thread, inbox),
      };

      if (filter === "needs_action") {
        if (enriched.your_status === "pending" && thread.status === "open") {
          threads.push(enriched);
        }
      } else if (filter === "open") {
        if (thread.status === "open") threads.push(enriched);
      } else if (filter === "closed") {
        if (thread.status === "closed") threads.push(enriched);
      } else {
        threads.push(enriched);
      }
    }

    threads.sort((a, b) => b.updated_at.localeCompare(a.updated_at));
    return { threads };
  }

  async getThread(
    auth: AuthContext,
    threadId: string,
  ): Promise<{
    thread: ThreadMeta;
    messages: ThreadMessage[];
    pending_downgrade?: ThreadDowngradeProposal;
  }> {
    const inbox = await this.getInboxEntry(auth.userId, threadId);
    if (!inbox) throw forbidden("Not a thread participant");

    const threadRes = await this.kv.get<ThreadMeta>(this.threadKey(threadId));
    const thread = threadRes.value ? this.normalizeThread(threadRes.value) : null;
    if (!thread || !this.threadVisibleToOrg(auth, thread)) throw notFound("Thread");

    const messages: ThreadMessage[] = [];
    const iter = this.kv.list<ThreadMessage>({ prefix: this.messagesPrefix(threadId) });
    for await (const entry of iter) {
      const msg = entry.value;
      if (this.canViewMessage(auth, thread, inbox, msg)) {
        messages.push(await this.hydrateMessage(thread, msg));
      }
    }
    messages.sort((a, b) => a.created_at.localeCompare(b.created_at));

    const enriched = await Promise.all(
      messages.map(async (msg) => ({
        ...msg,
        upvotes: await this.getMessageUpvoteSummary(auth, threadId, msg.id),
      })),
    );

    const pending = await getPendingThreadDowngrade(
      this.downgradeCtx(),
      auth,
      threadId,
    );

    return {
      thread: {
        ...thread,
        your_status: this.effectiveYourStatus(auth, thread, inbox),
      },
      messages: enriched,
      ...(pending ? { pending_downgrade: pending } : {}),
    };
  }

  /**
   * Web/MCP pull — returns app_envelope content for an authorized participant.
   * Rejects E2E threads (blind courier; use getThread for envelopes).
   * Optional `agent_id` must belong to the caller (attribution for hosted MCP).
   */
  async fetchAppMessages(
    auth: AuthContext,
    threadId: string,
    input: FetchAppMessagesInput = {},
  ): Promise<{ thread: ThreadMeta; messages: ThreadMessage[] }> {
    if (input.agent_id?.trim()) {
      const agent = await this.getAgent(input.agent_id.trim());
      if (!agent || agent.user_id !== auth.userId) {
        throw forbidden("agent_id does not belong to caller");
      }
    }

    const inbox = await this.getInboxEntry(auth.userId, threadId);
    if (!inbox) throw forbidden("Not a thread participant");

    const threadRes = await this.kv.get<ThreadMeta>(this.threadKey(threadId));
    const thread = threadRes.value ? this.normalizeThread(threadRes.value) : null;
    if (!thread || !this.threadVisibleToOrg(auth, thread)) throw notFound("Thread");

    if (thread.encryption_mode !== "app_envelope") {
      throw new HubError(
        "Thread is E2E — app_envelope fetch not available",
        "invalid_argument",
        400,
      );
    }

    const messages: ThreadMessage[] = [];
    const iter = this.kv.list<ThreadMessage>({ prefix: this.messagesPrefix(threadId) });
    for await (const entry of iter) {
      const msg = entry.value;
      if (!this.canViewMessage(auth, thread, inbox, msg)) continue;
      // Pre-downgrade E2E history stays sealed for web joiners (§4.2 rule 4).
      if (!messageVisibleAfterDowngrade(thread, msg)) continue;
      const hydrated = await this.hydrateMessage(thread, msg, { requireApp: true });
      messages.push(hydrated);
    }
    messages.sort((a, b) => a.created_at.localeCompare(b.created_at));

    return {
      thread: {
        ...thread,
        your_status: this.effectiveYourStatus(auth, thread, inbox),
      },
      messages,
    };
  }

  async toggleMessageUpvote(
    auth: AuthContext,
    threadId: string,
    messageId: string,
    input: ToggleUpvoteInput,
  ): Promise<ToggleUpvoteResult> {
    const inbox = await this.getInboxEntry(auth.userId, threadId);
    if (!inbox) throw forbidden("Not a thread participant");

    const threadRes = await this.kv.get<ThreadMeta>(this.threadKey(threadId));
    const thread = threadRes.value ? this.normalizeThread(threadRes.value) : null;
    if (!thread || !this.threadVisibleToOrg(auth, thread)) throw notFound("Thread");

    const msgRes = await this.kv.get<ThreadMessage>(this.messageKey(threadId, messageId));
    const msg = msgRes.value;
    if (!msg || msg.thread_id !== threadId) throw notFound("Message");
    if (!this.canViewMessage(auth, thread, inbox, msg)) {
      throw forbidden("Cannot upvote this message");
    }

    const user = await this.getUser(auth.userId);
    if (!user?.handle) throw notFound("User");

    const userParts = parseUserHandle(user.handle);
    const fromAgent = await this.resolveSenderAgent(auth.userId, {
      from_agent_id: input.from_agent_id,
      from_agent: input.from_agent,
    });
    const fromDisplay = formatDisplayAddress(userParts.local, userParts.orgSlug, fromAgent.slug);

    const voteKey = this.messageUpvoteKey(threadId, messageId, fromAgent.id);
    const existing = await this.kv.get(voteKey);
    if (existing.value) {
      await this.kv.delete(voteKey);
    } else {
      await this.kv.set(voteKey, {
        thread_id: threadId,
        message_id: messageId,
        agent_id: fromAgent.id,
        from_user_id: user.id,
        from_handle: fromDisplay,
        created_at: nowIso(),
      });
    }

    const upvotes = await this.getMessageUpvoteSummary(auth, threadId, messageId);
    const upvoted = upvotes.your_upvotes?.includes(fromAgent.id) ?? false;
    return { upvoted, upvotes };
  }

  private async getMessageUpvoteSummary(
    auth: AuthContext,
    threadId: string,
    messageId: string,
  ): Promise<MessageUpvoteSummary> {
    const upvotes: MessageUpvote[] = [];
    const yourUpvotes: string[] = [];
    const userAgentIds = new Set(await this.listAgentIdsForUser(auth.userId));

    const iter = this.kv.list<{
      agent_id: string;
      from_user_id: string;
      from_handle: string;
      created_at: string;
    }>({ prefix: this.messageUpvotesPrefix(threadId, messageId) });

    for await (const entry of iter) {
      const v = entry.value;
      upvotes.push({
        agent_id: v.agent_id,
        from_handle: v.from_handle,
        created_at: v.created_at,
      });
      if (v.from_user_id === auth.userId && userAgentIds.has(v.agent_id)) {
        yourUpvotes.push(v.agent_id);
      }
    }

    upvotes.sort((a, b) => a.created_at.localeCompare(b.created_at));
    return {
      count: upvotes.length,
      upvotes,
      ...(yourUpvotes.length > 0 ? { your_upvotes: yourUpvotes } : {}),
    };
  }

  private async listAgentIdsForUser(userId: string): Promise<string[]> {
    const ids: string[] = [];
    const iter = this.kv.list<string>({ prefix: this.userAgentsPrefix(userId) });
    for await (const entry of iter) {
      if (entry.value) ids.push(entry.value);
    }
    return ids;
  }

  async postReply(
    auth: AuthContext,
    threadId: string,
    input: ReplyInput,
  ): Promise<{ message_id: string }> {
    const wireKind = assertExclusiveWireUnit(input);
    if (wireKind === "e2e") {
      this.assertEnvelopeSize(input.envelope!);
    }

    const inbox = await this.getInboxEntry(auth.userId, threadId);
    if (!inbox) throw forbidden("Not a thread participant");

    const threadRes = await this.kv.get<ThreadMeta>(this.threadKey(threadId));
    const thread = threadRes.value ? this.normalizeThread(threadRes.value) : null;
    if (!thread || !this.threadVisibleToOrg(auth, thread)) throw notFound("Thread");
    if (thread.status === "closed") {
      throw new HubError("Thread is closed", "thread_closed", 409);
    }

    if (thread.external_link_id) {
      await assertExternalLinkVelocity(
        this.pairingCtx(),
        thread.external_link_id,
      );
    }

    const user = await this.getUser(auth.userId);
    if (!user?.handle) throw notFound("User");

    const userParts = parseUserHandle(user.handle);
    const fromAgent = await this.resolveSenderAgent(auth.userId, {
      from_agent_id: input.from_agent_id,
      from_agent: input.from_agent,
    });
    const fromDisplay = formatDisplayAddress(userParts.local, userParts.orgSlug, fromAgent.slug);

    // Enterprise agents may only reply within billed threads (§7.3 / §12).
    await this.enterprise.assertEnterpriseAgentSend(fromAgent.id, {
      thread_id: threadId,
      is_new_thread: false,
    });

    // Web slots cannot join E2E threads until unanimous downgrade (§6.5 / §7.3).
    if (thread.encryption_mode === "e2e" && fromAgent.transport === "mcp") {
      throw new HubError(
        "Web agents cannot join E2E threads until downgrade is approved",
        "downgrade_required",
        403,
      );
    }

    // Wire unit must match thread mode — never mix (§4.2.1).
    if (thread.encryption_mode === "e2e" && wireKind !== "e2e") {
      throw new HubError(
        "E2E threads require envelope (not app_envelope)",
        "invalid_argument",
        400,
      );
    }
    if (thread.encryption_mode === "app_envelope" && wireKind !== "app_envelope") {
      throw new HubError(
        "app_envelope threads require app_envelope payload (not E2E envelope)",
        "invalid_argument",
        400,
      );
    }

    const messageId = crypto.randomUUID();
    const ts = nowIso();

    const parentId = input.parent_message_id?.trim();
    if (parentId) {
      const parentRes = await this.kv.get<ThreadMessage>(
        this.messageKey(threadId, parentId),
      );
      if (!parentRes.value || parentRes.value.thread_id !== threadId) {
        throw new HubError(
          "Unknown parent message for this thread",
          "invalid_reply",
          400,
        );
      }
    }

    let updatedThread: ThreadMeta = {
      ...thread,
      reply_count: thread.reply_count + 1,
      updated_at: ts,
    };

    if (input.to_agent?.trim()) {
      const toAgent = await this.resolveAgentForUser(auth.userId, input.to_agent.trim());
      if (fromAgent.id === toAgent.id) {
        throw new HubError(
          `Cannot hand off to the same agent (${fromAgent.slug}). Use a different to_agent slug.`,
          "invalid_reply",
          400,
        );
      }
      // Adding a web agent to an E2E thread requires downgrade consent (§6.5).
      if (thread.encryption_mode === "e2e" && toAgent.transport === "mcp") {
        throw new HubError(
          `Cannot add @${toAgent.slug} (web) to an E2E thread — propose a downgrade first (POST …/downgrade-proposals)`,
          "downgrade_required",
          403,
        );
      }
      updatedThread = {
        ...updatedThread,
        audience: formatDisplayAddress(userParts.local, userParts.orgSlug, toAgent.slug),
        audience_agent_id: toAgent.id,
        audience_wire_path: formatWirePath(userParts.orgSlug, userParts.local, toAgent.slug),
      };
    }

    const message: ThreadMessage = {
      id: messageId,
      thread_id: threadId,
      from_user_id: user.id,
      from_handle: fromDisplay,
      from_agent_id: fromAgent.id,
      content_store: thread.encryption_mode,
      created_at: ts,
      // Org @all@org announcements hide peer replies; bare @all group threads share them.
      sender_only: thread.kind === "broadcast" && isBroadcastHandle(thread.audience),
      ...(parentId ? { parent_message_id: parentId } : {}),
      ...(thread.encryption_mode === "e2e" ? { envelope: input.envelope! } : {}),
    };

    const payloadBytes = thread.encryption_mode === "app_envelope"
      ? new TextEncoder().encode(JSON.stringify(input.app_envelope)).byteLength
      : 0;

    // Debit customer→enterprise follow-ups on store (enterprise replies are free).
    const enterpriseAgent = thread.enterprise_listing_id
      ? await this.enterprise.findListingByAgentId(fromAgent.id)
      : null;
    const shouldDebitEnterprise = Boolean(
      thread.enterprise_listing_id &&
        (!enterpriseAgent ||
          enterpriseAgent.id !== thread.enterprise_listing_id),
    );

    for (let attempt = 0; attempt < 8; attempt++) {
      let debitPlan: Awaited<
        ReturnType<EnterpriseStore["planEnterpriseDebit"]>
      > | null = null;
      if (shouldDebitEnterprise && thread.enterprise_listing_id) {
        debitPlan = await this.enterprise.planEnterpriseDebit(auth, {
          listing_id: thread.enterprise_listing_id,
          thread_id: threadId,
          payload_bytes: payloadBytes,
          blob_count: 0,
        });
      }

      const tx = this.kv.atomic();
      tx.set(this.messageKey(threadId, messageId), message);
      tx.set(this.threadKey(threadId), updatedThread);

      if (thread.encryption_mode === "app_envelope") {
        const record = await buildAppEnvelopeRecord({
          threadId,
          messageId,
          fromUserId: user.id,
          fromAgentId: fromAgent.id,
          createdAt: ts,
          payload: this.normalizeAppPayload(input.app_envelope!),
        });
        tx.set(this.appEnvelopeKey(threadId, messageId), record, {
          expireIn: APP_ENVELOPE_RETENTION_MS,
        });
      }

      if (debitPlan) debitPlan.apply(tx);

      tx.set(this.inboxKey(auth.userId, threadId), {
        ...inbox,
        your_status: "replied",
        updated_at: ts,
      });
      // Self-collab shares one inbox key — never re-write auth.userId here
      // (that clobbers replied back to a stale pending).
      if (thread.from_user_id === auth.userId) {
        // OP correction / follow-up: bump every other participant to Needs you.
        const peerIds = await this.listThreadPeerUserIds(thread, auth.userId);
        for (const peerId of peerIds) {
          const peerInbox = await this.getInboxEntry(peerId, threadId);
          if (!peerInbox) continue;
          tx.set(this.inboxKey(peerId, threadId), {
            ...peerInbox,
            your_status: "pending",
            updated_at: ts,
          });
        }
      } else {
        // Recipient reply: only the original sender needs action (broadcast
        // replies are sender-only — do not wake other recipients).
        const senderInbox = await this.getInboxEntry(thread.from_user_id, threadId);
        if (senderInbox) {
          tx.set(this.inboxKey(thread.from_user_id, threadId), {
            ...senderInbox,
            your_status: "pending",
            updated_at: ts,
          });
        }
      }
      const res = await tx.commit();
      if (res.ok) return { message_id: messageId };
    }
    throw new HubError("Failed to post reply", "internal", 500);
  }

  async closeThread(auth: AuthContext, threadId: string): Promise<{ thread: ThreadMeta }> {
    const inbox = await this.getInboxEntry(auth.userId, threadId);
    if (!inbox) throw forbidden("Not a thread participant");

    const threadRes = await this.kv.get<ThreadMeta>(this.threadKey(threadId));
    const thread = threadRes.value ? this.normalizeThread(threadRes.value) : null;
    if (!thread || !this.threadVisibleToOrg(auth, thread)) throw notFound("Thread");
    if (thread.status === "closed") {
      return {
        thread: {
          ...thread,
          your_status: this.effectiveYourStatus(auth, thread, inbox),
        },
      };
    }

    const updated: ThreadMeta = {
      ...thread,
      status: "closed",
      updated_at: nowIso(),
    };
    await this.kv.set(this.threadKey(threadId), updated);
    return {
      thread: {
        ...updated,
        your_status: this.effectiveYourStatus(auth, updated, inbox),
      },
    };
  }

  /**
   * Remove thread from the caller's inbox.
   * Sender also purges messages + thread + app_envelope payloads and clears
   * every org member's inbox for this thread. If the thread body is already
   * gone, still drops the caller's orphan inbox row (so recipients can dismiss
   * after a sender purge).
   */
  async deleteThread(auth: AuthContext, threadId: string): Promise<{ ok: true }> {
    const inbox = await this.getInboxEntry(auth.userId, threadId);
    if (!inbox) throw forbidden("Not a thread participant");

    const threadRes = await this.kv.get<ThreadMeta>(this.threadKey(threadId));
    const thread = threadRes.value;

    // Orphan inbox (sender already purged body) — just drop our row.
    if (!thread) {
      await this.kv.delete(this.inboxKey(auth.userId, threadId));
      return { ok: true };
    }
    if (!this.threadVisibleToOrg(auth, thread)) throw notFound("Thread");

    if (thread.from_user_id === auth.userId) {
      // Collect keys, then delete in atomic batches (inboxes first so a
      // mid-purge crash never leaves recipients pointing at a missing body).
      const memberIds = await this.listMemberIds(auth.orgId);
      const inboxUserIds = new Set<string>([auth.userId, thread.from_user_id, ...memberIds]);
      const inboxKeys: Deno.KvKey[] = [...inboxUserIds].map((uid) =>
        this.inboxKey(uid, threadId)
      );

      const bodyKeys: Deno.KvKey[] = [];
      const msgIter = this.kv.list<ThreadMessage>({
        prefix: this.messagesPrefix(threadId),
      });
      for await (const entry of msgIter) {
        const messageId = entry.key[entry.key.length - 1] as string;
        const upvoteIter = this.kv.list({
          prefix: this.messageUpvotesPrefix(threadId, messageId),
        });
        for await (const upvote of upvoteIter) {
          bodyKeys.push(upvote.key);
        }
        bodyKeys.push(entry.key);
      }
      // §4.6: thread delete removes app_envelope payloads for all participants.
      const appIter = this.kv.list({ prefix: this.appEnvelopesPrefix(threadId) });
      for await (const entry of appIter) {
        bodyKeys.push(entry.key);
      }
      bodyKeys.push(this.threadKey(threadId));

      await this.deleteKeysAtomic(inboxKeys);
      await this.deleteKeysAtomic(bodyKeys);
    } else {
      await this.kv.delete(this.inboxKey(auth.userId, threadId));
    }

    return { ok: true };
  }

  /** Deno KV allows ≤1000 mutations per atomic; batch larger purges. */
  private async deleteKeysAtomic(keys: Deno.KvKey[]): Promise<void> {
    const batchSize = 500;
    for (let i = 0; i < keys.length; i += batchSize) {
      const chunk = keys.slice(i, i + batchSize);
      let tx = this.kv.atomic();
      for (const key of chunk) {
        tx = tx.delete(key);
      }
      const res = await tx.commit();
      if (!res.ok) throw conflict("Thread delete raced; retry");
    }
  }

  async listDrafts(auth: AuthContext): Promise<{ drafts: Draft[] }> {
    const drafts: Draft[] = [];
    const iter = this.kv.list<Draft>({ prefix: this.draftsPrefix(auth.userId) });
    for await (const entry of iter) {
      if (entry.value.org_id === auth.orgId) drafts.push(entry.value);
    }
    drafts.sort((a, b) => b.updated_at.localeCompare(a.updated_at));
    return { drafts };
  }

  async getDraft(auth: AuthContext, draftId: string): Promise<Draft> {
    const res = await this.kv.get<Draft>(this.draftKey(auth.userId, draftId));
    const draft = res.value;
    if (!draft || draft.org_id !== auth.orgId) throw notFound("Draft");
    return draft;
  }

  async createDraft(auth: AuthContext, envelope: Envelope): Promise<Draft> {
    this.assertEnvelopeSize(envelope);
    const id = crypto.randomUUID();
    const ts = nowIso();
    const draft: Draft = {
      id,
      user_id: auth.userId,
      org_id: auth.orgId,
      envelope,
      created_at: ts,
      updated_at: ts,
    };
    await this.kv.set(this.draftKey(auth.userId, id), draft);
    return draft;
  }

  async updateDraft(
    auth: AuthContext,
    draftId: string,
    envelope: Envelope,
  ): Promise<Draft> {
    this.assertEnvelopeSize(envelope);
    const existing = await this.getDraft(auth, draftId);
    const updated: Draft = { ...existing, envelope, updated_at: nowIso() };
    await this.kv.set(this.draftKey(auth.userId, draftId), updated);
    return updated;
  }

  async deleteDraft(auth: AuthContext, draftId: string): Promise<void> {
    await this.getDraft(auth, draftId);
    await this.kv.delete(this.draftKey(auth.userId, draftId));
  }

  async createUploadUrl(
    auth: AuthContext,
    sizeBytes: number,
    contentType?: string,
  ): Promise<{ blob_id: string; upload_url: string; expires_at: string }> {
    if (sizeBytes <= 0) throw new HubError("size_bytes must be positive", "invalid_size");
    const quotaRes = await this.kv.get<number>(this.orgQuotaKey(auth.orgId));
    const quota = quotaRes.value ?? 0;
    if (quota + sizeBytes > ORG_BLOB_QUOTA_BYTES) throw quotaExceeded();

    const blobId = crypto.randomUUID();
    const ts = nowIso();
    const meta: BlobMeta = {
      id: blobId,
      org_id: auth.orgId,
      owner_user_id: auth.userId,
      size_bytes: sizeBytes,
      content_type: contentType,
      created_at: ts,
    };

    const tx = this.kv.atomic();
    tx.check(quotaRes);
    tx.set(this.blobKey(blobId), meta);
    tx.set(this.orgQuotaKey(auth.orgId), quota + sizeBytes);
    const res = await tx.commit();
    if (!res.ok) throw conflict("Blob quota update conflict; retry");

    const { url, expires_at } = await createBlobUrls(blobId, "PUT", {
      contentType,
    });
    return {
      blob_id: blobId,
      upload_url: url,
      expires_at,
    };
  }

  async createDownloadUrl(
    auth: AuthContext,
    blobId: string,
  ): Promise<{ download_url: string; expires_at: string; meta: BlobMeta }> {
    const res = await this.kv.get<BlobMeta>(this.blobKey(blobId));
    const meta = res.value;
    if (!meta) throw notFound("Blob");
    if (meta.org_id !== auth.orgId) throw forbidden("Blob belongs to another org");

    const { url, expires_at } = await createBlobUrls(blobId, "GET");
    return {
      download_url: url,
      expires_at,
      meta,
    };
  }

  private async getUser(id: string): Promise<User | null> {
    const res = await this.kv.get<User>(this.userKey(id));
    return res.value;
  }

  private async getUserByHandle(handle: string): Promise<User | null> {
    const map = await this.kv.get<string>(this.handleKey(handle));
    if (!map.value) return null;
    return this.getUser(map.value);
  }

  private async getOrg(id: string): Promise<Org | null> {
    const res = await this.kv.get<Org>(this.orgKey(id));
    return res.value;
  }

  private async getInboxEntry(userId: string, threadId: string): Promise<InboxEntry | null> {
    const res = await this.kv.get<InboxEntry>(this.inboxKey(userId, threadId));
    return res.value;
  }

  /**
   * Other users who already have an inbox row for this thread (exclude caller).
   * Uses participant_user_ids when present (cross-org); otherwise org members.
   */
  private async listThreadPeerUserIds(
    thread: ThreadMeta,
    excludeUserId: string,
  ): Promise<string[]> {
    const candidates = new Set<string>();
    if (thread.participant_user_ids?.length) {
      for (const uid of thread.participant_user_ids) candidates.add(uid);
    } else {
      candidates.add(thread.from_user_id);
      for (const uid of await this.listMemberIds(thread.org_id)) {
        candidates.add(uid);
      }
    }
    candidates.delete(excludeUserId);
    const peers: string[] = [];
    for (const uid of candidates) {
      if (await this.getInboxEntry(uid, thread.id)) peers.push(uid);
    }
    return peers;
  }

  /**
   * User-scoped inbox status for the Mac UI.
   * Self-collab outbound (own agent / bare @all / sole-member broadcast) must
   * read as Waiting — not Needs you — while unreplied. Agent MCP remaps
   * audience-ball pending in the daemon.
   */
  private effectiveYourStatus(
    auth: AuthContext,
    thread: ThreadMeta,
    inbox: InboxEntry,
  ): "pending" | "replied" {
    // One inbox key per user cannot express per-agent pending. Self-collab
    // (own agents / @all) is Waiting for the human Mac inbox — heal stale
    // pending rows from older create/reply clobbers.
    if (
      inbox.your_status === "pending" &&
      thread.from_user_id === auth.userId &&
      this.isSelfCollabOutbound(thread)
    ) {
      return "replied";
    }
    return inbox.your_status;
  }

  private isSelfCollabOutbound(thread: ThreadMeta): boolean {
    if (thread.kind === "direct") {
      return stripAgentSuffix(thread.from) === stripAgentSuffix(thread.audience);
    }
    // Bare @all, or org @all@slug delivered only to self (sole member).
    return thread.audience === myAgentsHandle() || thread.audience.startsWith("@all@");
  }

  private async listMemberIds(orgId: string, excludeUserId?: string): Promise<string[]> {
    const ids: string[] = [];
    const iter = this.kv.list<string>({ prefix: this.membersPrefix(orgId) });
    for await (const entry of iter) {
      const userId = entry.value;
      if (excludeUserId && userId === excludeUserId) continue;
      ids.push(userId);
    }
    return ids;
  }

  private async getAgent(id: string): Promise<Agent | null> {
    const res = await this.kv.get<Agent>(this.agentKey(id));
    if (!res.value) return null;
    return normalizeAgent(res.value);
  }

  private async loadTransportPrefs(userId: string): Promise<AgentTransportPrefs> {
    const stored = await this.kv.get<AgentTransportPrefs>(this.userTransportPrefsKey(userId));
    if (!stored.value?.defaults) return emptyTransportPrefs();
    const defaults: Record<string, AgentTransport> = {};
    for (const [slug, transport] of Object.entries(stored.value.defaults)) {
      if (isAgentTransport(transport)) defaults[slug] = transport;
    }
    return { defaults };
  }

  /** Look up agent_id for (slug, transport), including legacy sidecar slug index. */
  private async lookupAgentSlotId(
    userId: string,
    slug: string,
    transport: AgentTransport,
  ): Promise<string | null> {
    const slot = await this.kv.get<string>(this.userAgentSlotKey(userId, slug, transport));
    if (slot.value) return slot.value;
    if (transport === "sidecar") {
      const legacy = await this.kv.get<string>(this.userAgentSlugKey(userId, slug));
      if (legacy.value) {
        const agent = await this.getAgent(legacy.value);
        // Legacy 3-part key is the pre-L1 single slot (= sidecar).
        if (agent?.transport === "sidecar") return legacy.value;
      }
    }
    return null;
  }

  private async ensureSlotIndex(userId: string, agent: Agent): Promise<void> {
    await this.kv.set(this.userAgentSlotKey(userId, agent.slug, agent.transport), agent.id);
    if (agent.transport === "sidecar") {
      await this.kv.set(this.userAgentSlugKey(userId, agent.slug), agent.id);
    }
  }

  /** Load router; migrate from slug index + default when missing. */
  private async loadRouter(userId: string): Promise<RouterConfig> {
    const stored = await this.kv.get<RouterConfig>(this.userRouterKey(userId));
    if (stored.value) {
      return {
        default_agent_id: stored.value.default_agent_id ?? null,
        rules: [...(stored.value.rules ?? [])].sort((a, b) =>
          a.match_slug.localeCompare(b.match_slug)
        ),
      };
    }

    const rules: RoutingRule[] = [];
    const seenSlugs = new Set<string>();
    const iter = this.kv.list<string>({ prefix: this.userAgentsPrefix(userId) });
    for await (const entry of iter) {
      const agent = await this.getAgent(entry.value);
      if (!agent || seenSlugs.has(agent.slug)) continue;
      seenSlugs.add(agent.slug);
      rules.push({ match_slug: agent.slug, agent_id: agent.id });
    }
    rules.sort((a, b) => a.match_slug.localeCompare(b.match_slug));
    const defaultRes = await this.kv.get<string>(this.userDefaultAgentKey(userId));
    const router: RouterConfig = {
      default_agent_id: defaultRes.value ?? null,
      rules,
    };
    if (rules.length > 0 || router.default_agent_id) {
      await this.kv.set(this.userRouterKey(userId), router);
    }
    return router;
  }

  private async normalizeRules(userId: string, rules: RoutingRule[]): Promise<RoutingRule[]> {
    const seen = new Set<string>();
    const out: RoutingRule[] = [];
    for (const rule of rules) {
      const matchSlug = rule.match_slug.trim().toLowerCase();
      assertValidAgentSlug(matchSlug);
      if (seen.has(matchSlug)) {
        throw new HubError(`Duplicate router rule for '${matchSlug}'`, "invalid_router", 400);
      }
      const agent = await this.getAgent(rule.agent_id);
      if (!agent || agent.user_id !== userId) {
        throw notFound("Agent");
      }
      seen.add(matchSlug);
      out.push({ match_slug: matchSlug, agent_id: agent.id });
    }
    out.sort((a, b) => a.match_slug.localeCompare(b.match_slug));
    return out;
  }

  /**
   * Sender for create/reply/upvote: explicit `from_agent_id` (owned by caller) wins;
   * otherwise slug / default via [resolveAgentForUser].
   */
  private async resolveSenderAgent(
    userId: string,
    input: { from_agent_id?: string; from_agent?: string },
  ): Promise<Agent> {
    const id = input.from_agent_id?.trim();
    if (id) {
      const agent = await this.getAgent(id);
      if (!agent || agent.user_id !== userId) {
        throw forbidden("from_agent_id does not belong to caller");
      }
      return agent;
    }
    return this.resolveAgentForUser(userId, input.from_agent);
  }

  /**
   * Resolve agent for address routing.
   * Bare → default agent. Slug → router rule, else preferred transport slot, else any slot.
   * Capability staleness never blocks resolution.
   * Renamed slugs fail with a clear hint (no silent redirect).
   */
  private async resolveAgentForUser(userId: string, slug?: string): Promise<Agent> {
    const router = await this.loadRouter(userId);

    if (slug?.trim()) {
      const normalized = slug.trim().toLowerCase();

      // Explicit router rule wins (may point at either transport row).
      const rule = router.rules.find((r) => r.match_slug === normalized);
      if (rule) {
        const agent = await this.getAgent(rule.agent_id);
        if (agent) return agent;
      }

      const prefs = await this.loadTransportPrefs(userId);
      const preferred: AgentTransport = prefs.defaults[normalized] ?? "sidecar";
      const preferredId = await this.lookupAgentSlotId(userId, normalized, preferred);
      if (preferredId) {
        const agent = await this.getAgent(preferredId);
        if (agent) return agent;
      }
      const fallbackTransport: AgentTransport = preferred === "sidecar" ? "mcp" : "sidecar";
      const fallbackId = await this.lookupAgentSlotId(userId, normalized, fallbackTransport);
      if (fallbackId) {
        const agent = await this.getAgent(fallbackId);
        if (agent) return agent;
      }

      const alias = await this.kv.get<{ agent_id: string; current_slug: string }>(
        this.userAgentAliasKey(userId, normalized),
      );
      if (alias.value?.current_slug) {
        throw new HubError(
          `Agent '${normalized}' was renamed to '${alias.value.current_slug}'. Use the new address.`,
          "agent_renamed",
          400,
        );
      }

      throw new HubError(`Unknown agent '${normalized}'`, "unknown_agent", 400);
    }

    if (router.default_agent_id) {
      const agent = await this.getAgent(router.default_agent_id);
      if (agent) return agent;
    }

    throw new HubError("No default agent registered", "unknown_agent", 400);
  }

  private async assertSameOrgHandle(orgId: string, handle: string): Promise<void> {
    const bare = stripAgentSuffix(handle);
    const { orgSlug } = parseUserHandle(bare);
    const org = await this.getOrg(orgId);
    if (!org || org.slug !== orgSlug) {
      throw forbidden("Recipient must be in your org");
    }
  }

  /** Legacy rows without encryption_mode → e2e. */
  private normalizeThread(thread: ThreadMeta): ThreadMeta {
    return {
      ...thread,
      encryption_mode: normalizeEncryptionMode(thread.encryption_mode),
    };
  }

  /**
   * Same-org threads: org_id must match.
   * Enterprise billed / external-contact threads: inbox participation is enough (cross-org).
   */
  private threadVisibleToOrg(auth: AuthContext, thread: ThreadMeta): boolean {
    if (thread.enterprise_listing_id) return true;
    if (thread.external_link_id) return true;
    if (thread.participant_user_ids?.includes(auth.userId)) return true;
    return thread.org_id === auth.orgId;
  }

  private normalizeAppPayload(raw: AppEnvelopePayload): AppEnvelopePayload {
    const version = typeof raw.version === "number" && raw.version >= 1 ? raw.version : 1;
    return { ...raw, version };
  }

  /**
   * Hydrate message body from the correct store. Never attaches both envelope
   * and app_envelope (§4.2.1).
   */
  private async hydrateMessage(
    thread: ThreadMeta,
    msg: ThreadMessage,
    opts?: { requireApp?: boolean },
  ): Promise<ThreadMessage> {
    const mode = normalizeEncryptionMode(thread.encryption_mode);
    // Per-message store wins — downgraded threads keep pre-point E2E history sealed.
    const store = msg.content_store ??
      (msg.envelope ? "e2e" : (msg.app_envelope ? "app_envelope" : mode));

    if (store === "app_envelope") {
      const recordRes = await this.kv.get<
        import("./app_envelope.ts").AppEnvelopeRecord
      >(this.appEnvelopeKey(thread.id, msg.id));
      if (!recordRes.value) {
        if (opts?.requireApp) {
          throw notFound("App envelope");
        }
        // Expired (30d) or purged — return metadata only.
        const { envelope: _drop, app_envelope: _a, ...rest } = msg;
        return { ...rest, content_store: "app_envelope" };
      }
      const payload = await openAppEnvelope(recordRes.value);
      const { envelope: _drop, ...rest } = msg;
      return {
        ...rest,
        content_store: "app_envelope",
        app_envelope: payload,
      };
    }

    // E2E — strip any accidental app_envelope field.
    const { app_envelope: _a, ...rest } = msg;
    return { ...rest, content_store: "e2e" };
  }

  private canViewMessage(
    auth: AuthContext,
    thread: ThreadMeta,
    inbox: InboxEntry,
    msg: ThreadMessage,
  ): boolean {
    if (msg.from_user_id === auth.userId) return true;
    if (thread.kind === "broadcast" && msg.sender_only) {
      return inbox.role === "sender";
    }
    return true;
  }

  async createOrgForUser(claims: Auth0Claims, input: CreateOrgInput): Promise<MeResponse> {
    await this.createOrgWithAdmin(claims, input);
    return this.getMe(claims);
  }

  /**
   * Org-admin typo fix: rename org slug and rewrite every member's live handle.
   * Historical thread addresses are left unchanged (same as personal handle rename).
   */
  async updateOrgSlug(auth: AuthContext, input: UpdateOrgInput): Promise<MeResponse> {
    if (auth.role !== "org_admin") throw forbidden("Org admin required");
    const newSlug = input.slug.trim().toLowerCase();
    assertValidSlug(newSlug);

    const orgRes = await this.kv.get<Org>(this.orgKey(auth.orgId));
    const org = orgRes.value;
    if (!org) throw notFound("Org");

    if (org.slug === newSlug) {
      return this.getMe({ sub: auth.auth0Sub });
    }

    await this.enterprise.assertOrgSlugAvailable(newSlug);
    const newSlugRes = await this.kv.get(this.orgSlugKey(newSlug));
    if (newSlugRes.value) {
      throw conflict(`Org slug '${newSlug}' already exists`);
    }

    const oldSlug = org.slug;
    const memberIds = await this.listMemberIds(auth.orgId);
    type MemberRename = {
      user: User;
      userRes: Deno.KvEntryMaybe<User>;
      oldHandle: string;
      newHandle: string;
      oldHandleRes: Deno.KvEntryMaybe<unknown>;
      newHandleRes: Deno.KvEntryMaybe<unknown>;
    };
    const renames: MemberRename[] = [];

    for (const memberId of memberIds) {
      const userRes = await this.kv.get<User>(this.userKey(memberId));
      const user = userRes.value;
      if (!user?.handle) continue;
      const { local, orgSlug } = parseUserHandle(user.handle);
      if (orgSlug !== oldSlug) {
        throw new HubError(
          `Member handle '${user.handle}' is not in org '${oldSlug}'`,
          "internal",
          500,
        );
      }
      const newHandle = `${local}@${newSlug}`;
      const oldHandleRes = await this.kv.get(this.handleKey(user.handle));
      const newHandleRes = await this.kv.get(this.handleKey(newHandle));
      if (newHandleRes.value && newHandleRes.value !== user.id) {
        throw conflict(`Handle '${newHandle}' already registered`);
      }
      renames.push({
        user: { ...user, handle: newHandle },
        userRes,
        oldHandle: user.handle,
        newHandle,
        oldHandleRes,
        newHandleRes,
      });
    }

    const oldSlugRes = await this.kv.get(this.orgSlugKey(oldSlug));
    const updatedOrg: Org = { ...org, slug: newSlug };

    const tx = this.kv.atomic();
    tx.check(orgRes).check(oldSlugRes).check(newSlugRes);
    for (const r of renames) {
      tx.check(r.userRes).check(r.oldHandleRes).check(r.newHandleRes);
    }
    tx.set(this.orgKey(updatedOrg.id), updatedOrg);
    tx.delete(this.orgSlugKey(oldSlug));
    tx.set(this.orgSlugKey(newSlug), updatedOrg);
    for (const r of renames) {
      tx.set(this.userKey(r.user.id), r.user);
      if (r.oldHandle !== r.newHandle) {
        tx.delete(this.handleKey(r.oldHandle));
      }
      tx.set(this.handleKey(r.newHandle), r.user.id);
    }
    const res = await tx.commit();
    if (!res.ok) throw conflict("Org slug update conflict");

    return this.getMe({ sub: auth.auth0Sub });
  }

  async joinOrgWithInvite(claims: Auth0Claims, input: JoinOrgInput): Promise<MeResponse> {
    await this.joinOrg(claims, input);
    return this.getMe(claims);
  }

  /** Overload-friendly org-id invite create for tests/bootstrap. */
  async createInviteByOrgId(orgId: string, createdBy?: string): Promise<Invite> {
    const org = await this.getOrg(orgId);
    if (!org) throw notFound("Org");
    const invite: Invite = {
      code: randomToken(),
      org_id: orgId,
      created_at: nowIso(),
    };
    await this.kv.set(this.inviteKey(invite.code), invite);
    await this.kv.set(this.orgInviteKey(orgId, invite.code), invite.code);
    return invite;
  }

  async createInviteAsAdmin(
    auth: AuthContext,
    opts?: { email?: string },
  ): Promise<Invite> {
    return this.createInvite(auth, opts);
  }

  async submitFeedback(
    auth: AuthContext,
    input: {
      message: string;
      category?: string;
      app_version?: string;
      platform?: Feedback["platform"];
    },
  ): Promise<Feedback> {
    const message = input.message?.trim() ?? "";
    if (!message) {
      throw new HubError("message is required", "invalid_argument", 400);
    }
    if (message.length > 4000) {
      throw new HubError("message too long (max 4000)", "invalid_argument", 400);
    }
    const user = await this.getUser(auth.userId);
    const id = crypto.randomUUID();
    const created_at = nowIso();
    const feedback: Feedback = {
      id,
      created_at,
      user_id: auth.userId,
      handle: auth.handle,
      org_id: auth.orgId,
      auth0_sub: auth.auth0Sub,
      ...(user?.email ? { email: user.email } : {}),
      message,
      ...(input.category?.trim()
        ? { category: input.category.trim().slice(0, 64) }
        : {}),
      ...(input.app_version?.trim()
        ? { app_version: input.app_version.trim().slice(0, 64) }
        : {}),
      platform: input.platform ?? "macos",
    };
    await this.kv.set(this.feedbackKey(created_at, id), feedback);
    return feedback;
  }

  /** Product-owner ops: Auth0 SuperAdmin (not org_admin). */
  async listFeedback(auth: AuthContext): Promise<{ feedback: Feedback[] }> {
    if (!isPlatformOpsAdmin(auth.auth0Roles)) {
      throw forbidden("Platform admin required");
    }
    const items: Feedback[] = [];
    const iter = this.kv.list<Feedback>({ prefix: this.feedbackPrefix() });
    for await (const entry of iter) {
      if (entry.value) items.push(entry.value);
    }
    // Newest first (keys are ISO timestamps ascending).
    items.sort((a, b) => b.created_at.localeCompare(a.created_at));
    return { feedback: items };
  }

  async submitWaitlist(input: {
    email: string;
    ai_hosts: string[];
    oses: string[];
    share_frequency: string;
    share_methods: string[];
  }): Promise<WaitlistEntry> {
    const email = input.email?.trim().toLowerCase() ?? "";
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new HubError("valid email is required", "invalid_argument", 400);
    }
    if (email.length > 254) {
      throw new HubError("email too long", "invalid_argument", 400);
    }
    const ai_hosts = normalizeStringList(input.ai_hosts, "ai_hosts");
    const oses = normalizeStringList(input.oses, "oses");
    const share_frequency = clipRequired(
      input.share_frequency,
      "share_frequency",
      64,
    );
    const share_methods = normalizeStringList(
      input.share_methods,
      "share_methods",
    );
    const id = crypto.randomUUID();
    const created_at = nowIso();
    const entry: WaitlistEntry = {
      id,
      created_at,
      email,
      ai_hosts,
      oses,
      share_frequency,
      share_methods,
      source: "web",
    };
    await this.kv.set(this.waitlistKey(created_at, id), entry);
    return entry;
  }

  /** Product-owner ops: Auth0 SuperAdmin (same gate as feedback). */
  async listWaitlist(auth: AuthContext): Promise<{ waitlist: WaitlistEntry[] }> {
    if (!isPlatformOpsAdmin(auth.auth0Roles)) {
      throw forbidden("Platform admin required");
    }
    const items: WaitlistEntry[] = [];
    const iter = this.kv.list<WaitlistEntry>({ prefix: this.waitlistPrefix() });
    for await (const entry of iter) {
      if (entry.value) items.push(entry.value);
    }
    items.sort((a, b) => b.created_at.localeCompare(a.created_at));
    return { waitlist: items };
  }

  async listInvitesAsAdmin(auth: AuthContext): Promise<{ invites: Invite[] }> {
    return this.listInvites(auth);
  }

  async createOrg(slug: string, name?: string): Promise<Org> {
    const normalized = slug.trim().toLowerCase();
    assertValidSlug(normalized);
    await this.enterprise.assertOrgSlugAvailable(normalized);
    const existing = await this.kv.get(this.orgSlugKey(normalized));
    if (existing.value) throw conflict(`Org slug '${normalized}' already exists`);
    const org: Org = {
      id: crypto.randomUUID(),
      slug: normalized,
      name: name ?? normalized,
      created_at: nowIso(),
    };
    const tx = this.kv.atomic();
    tx.set(this.orgKey(org.id), org);
    tx.set(this.orgSlugKey(normalized), org);
    tx.set(this.orgQuotaKey(org.id), 0);
    const res = await tx.commit();
    if (!res.ok) throw new HubError("Failed to create org", "internal", 500);
    return org;
  }

}


export function createStore(
  kv: Deno.Kv,
  options?: { verifier?: TokenVerifier },
): HubStore {
  if (options?.verifier) return new HubStore(kv, options.verifier);

  const domain = Deno.env.get("AUTH0_DOMAIN");
  const audience = Deno.env.get("AUTH0_AUDIENCE");
  if (Deno.env.get("DENO_DEPLOYMENT_ID") && (!domain || !audience)) {
    throw new Error("AUTH0_DOMAIN and AUTH0_AUDIENCE must be set in production");
  }
  if (domain && audience) {
    const aliases = (Deno.env.get("AUTH0_ISSUER_ALIASES") ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    // Custom-domain ↔ tenant share JWKS; accept both while Deploy env catches up.
    if (domain === "auth.mutande.online" && !aliases.includes("chevrondigital.auth0.com")) {
      aliases.push("chevrondigital.auth0.com");
    }
    if (domain === "chevrondigital.auth0.com" && !aliases.includes("auth.mutande.online")) {
      aliases.push("auth.mutande.online");
    }
    // Default matches hosted MCP PRM resource so ChatGPT tokens (aud=MCP)
    // validate when MCP forwards the same Bearer (no OBO). Set empty to disable.
    const mcpAudRaw = Deno.env.get("AUTH0_MCP_AUDIENCE");
    const mcpAudience = mcpAudRaw === undefined
      ? "https://mcp.mutande.online"
      : (mcpAudRaw.trim() || null);
    return new HubStore(
      kv,
      createAuth0Verifier({ domain, audience, mcpAudience, issuerAliases: aliases }),
    );
  }
  return new HubStore(kv, {
    async verifyAccessToken() {
      throw unauthorized("AUTH0_DOMAIN and AUTH0_AUDIENCE must be configured");
    },
  });
}

export async function createStoreWithTestAuth(kv: Deno.Kv): Promise<{
  store: HubStore;
  signToken: (claims: Auth0Claims) => Promise<string>;
}> {
  const { verifier, signToken } = await createTestTokenVerifier();
  return { store: createStore(kv, { verifier }), signToken };
}

export type { UserRole };
