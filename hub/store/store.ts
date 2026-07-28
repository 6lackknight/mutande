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
import { randomToken } from "./jwt.ts";
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
  InboxEntry,
  Invite,
  JoinOrgInput,
  MeResponse,
  Org,
  RegisterDeviceInput,
  ReplyInput,
  Agent,
  SetDefaultAgentInput,
  RegisterAgentInput,
  RenameAgentInput,
  RouterConfig,
  RoutingRule,
  SetRouterInput,
  ThreadFilter,
  ThreadMessage,
  ThreadMeta,
  User,
  UserRole,
} from "./types.ts";
import { createBlobUrls } from "./r2.ts";
import { MAX_ENVELOPE_BYTES, ORG_BLOB_QUOTA_BYTES } from "./types.ts";
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

function authContextFromUser(user: User): AuthContext {
  if (!isOnboarded(user)) {
    throw forbidden("Onboarding required");
  }
  return {
    userId: user.id,
    orgId: user.org_id!,
    handle: user.handle!,
    role: primaryRole(user),
    auth0Sub: user.auth0_sub,
  };
}

export class HubStore {
  constructor(
    private readonly kv: Deno.Kv,
    private readonly verifier: TokenVerifier,
  ) {}

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
  private threadKey(id: string) { return ["threads", id]; }
  private inboxKey(userId: string, threadId: string) { return ["inbox", userId, threadId]; }
  private inboxPrefix(userId: string) { return ["inbox", userId]; }
  private messageKey(threadId: string, messageId: string) { return ["messages", threadId, messageId]; }
  private messagesPrefix(threadId: string) { return ["messages", threadId]; }
  private draftKey(userId: string, draftId: string) { return ["drafts", userId, draftId]; }
  private draftsPrefix(userId: string) { return ["drafts", userId]; }
  private blobKey(id: string) { return ["blobs", id]; }
  private orgQuotaKey(orgId: string) { return ["org_blob_quota", orgId]; }
  private agentKey(id: string) { return ["agents", id]; }
  private userAgentSlugKey(userId: string, slug: string) { return ["user_agent_slugs", userId, slug]; }
  private userAgentsPrefix(userId: string) { return ["user_agent_slugs", userId]; }
  private userDefaultAgentKey(userId: string) { return ["user_default_agent", userId]; }
  private userRouterKey(userId: string) { return ["user_router", userId]; }
  private userAgentAliasKey(userId: string, slug: string) { return ["user_agent_aliases", userId, slug]; }

  assertEnvelopeSize(envelope: Envelope): void {
    const size = new TextEncoder().encode(JSON.stringify(envelope)).byteLength;
    if (size > MAX_ENVELOPE_BYTES) throw envelopeTooLarge(size);
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
    const user = await this.getUserByAuth0Sub(claims.sub);
    const onboarded = isOnboarded(user);
    const org = user?.org_id ? await this.getOrg(user.org_id) : null;
    return {
      auth0_sub: claims.sub,
      email: claims.email ?? user?.email,
      onboarded,
      needs_onboarding: !onboarded,
      user: user ?? undefined,
      org: org ?? undefined,
    };
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
    return authContextFromUser(user!);
  }

  async createOrgWithAdmin(
    claims: Auth0Claims,
    input: CreateOrgInput,
  ): Promise<{ org: Org; user: User }> {
    const slug = input.slug.trim().toLowerCase();
    assertValidSlug(slug);
    const name = (input.name?.trim() || slug);

    if (await this.getUserByAuth0Sub(claims.sub)) {
      throw conflict("User already onboarded");
    }

    const local = input.handle
      ? parseUserHandle(input.handle.includes("@") ? input.handle : `${input.handle}@${slug}`).local
      : (emailLocalPart(claims.email) ?? "admin");
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
      assertHandleLocal(local);
      if (orgSlug !== org.slug) throw forbidden("Handle must belong to invite org");
      handle = `${local}@${org.slug}`;
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
    const device: Device = {
      id: crypto.randomUUID(),
      user_id: auth.userId,
      pubkey: input.pubkey.trim(),
      platform: input.platform,
      created_at: nowIso(),
    };
    const tx = this.kv.atomic();
    tx.set(this.deviceKey(device.id), device);
    tx.set(this.userDeviceKey(auth.userId, device.id), device.id);
    const res = await tx.commit();
    if (!res.ok) throw conflict("Device register conflict");
    return device;
  }

  async listDevices(auth: AuthContext): Promise<{ devices: Device[] }> {
    const devices: Device[] = [];
    const iter = this.kv.list<string>({ prefix: this.userDevicesPrefix(auth.userId) });
    for await (const entry of iter) {
      const device = await this.kv.get<Device>(this.deviceKey(entry.value));
      if (device.value) devices.push(device.value);
    }
    devices.sort((a, b) => a.created_at.localeCompare(b.created_at));
    return { devices };
  }

  async registerAgent(auth: AuthContext, input: RegisterAgentInput): Promise<Agent> {
    const slug = input.slug.trim().toLowerCase();
    assertValidAgentSlug(slug);
    const existing = await this.kv.get<string>(this.userAgentSlugKey(auth.userId, slug));
    if (existing.value) {
      const agent = await this.getAgent(existing.value);
      if (agent) return agent;
    }

    const agent: Agent = {
      id: crypto.randomUUID(),
      user_id: auth.userId,
      slug,
      created_at: nowIso(),
    };
    const router = await this.loadRouter(auth.userId);
    const rules = router.rules.filter((r) => r.match_slug !== slug);
    rules.push({ match_slug: slug, agent_id: agent.id });
    rules.sort((a, b) => a.match_slug.localeCompare(b.match_slug));
    const defaultAgentId = router.default_agent_id ?? agent.id;

    const tx = this.kv.atomic();
    tx.set(this.agentKey(agent.id), agent);
    tx.set(this.userAgentSlugKey(auth.userId, slug), agent.id);
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
    const agents: Agent[] = [];
    const iter = this.kv.list<string>({ prefix: this.userAgentsPrefix(auth.userId) });
    for await (const entry of iter) {
      const agent = await this.getAgent(entry.value);
      if (agent) agents.push(agent);
    }
    agents.sort((a, b) => a.slug.localeCompare(b.slug));
    const router = await this.loadRouter(auth.userId);
    return { agents, default_agent_id: router.default_agent_id };
  }

  async listAgentsForHandle(
    auth: AuthContext,
    handle: string,
  ): Promise<{ agents: Agent[] }> {
    const bare = stripAgentSuffix(handle.trim());
    await this.assertSameOrgHandle(auth.orgId, bare);
    const user = await this.getUserByHandle(bare);
    if (!user) throw notFound("User");
    const { agents } = await this.listAgents(authContextFromUser(user));
    return { agents };
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

    const taken = await this.kv.get<string>(this.userAgentSlugKey(auth.userId, newSlug));
    if (taken.value && taken.value !== agentId) {
      throw conflict("Agent slug already taken");
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

    const tx = this.kv.atomic();
    tx.delete(this.userAgentSlugKey(auth.userId, oldSlug));
    tx.set(this.userAgentSlugKey(auth.userId, newSlug), agent.id);
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
    const res = await tx.commit();
    if (!res.ok) throw conflict("Agent rename conflict");
    return updated;
  }

  async createInvite(auth: AuthContext): Promise<Invite> {
    if (auth.role !== "org_admin") throw forbidden("Org admin required");
    const org = await this.getOrg(auth.orgId);
    if (!org) throw notFound("Org");
    const invite: Invite = {
      code: randomToken(),
      org_id: auth.orgId,
      created_at: nowIso(),
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
    }];
    const iter = this.kv.list<string>({ prefix: this.membersPrefix(auth.orgId) });
    for await (const entry of iter) {
      const memberId = entry.value;
      if (memberId === auth.userId) continue;
      const user = await this.getUser(memberId);
      if (!user || !isOnboarded(user)) continue;
      const { devices } = await this.listDevices(authContextFromUser(user));
      const mapped = devices.map((d) => ({ pubkey: d.pubkey, platform: d.platform }));
      contacts.push({
        handle: user.handle!,
        pubkey: mapped[0]?.pubkey ?? user.pubkey ?? null,
        devices: mapped,
      });
    }
    contacts.sort((a, b) => a.handle.localeCompare(b.handle));
    return { contacts };
  }

  async createThread(auth: AuthContext, input: CreateThreadInput): Promise<{
    thread: ThreadMeta;
    message_id: string;
  }> {
    this.assertEnvelopeSize(input.envelope);
    const sender = await this.getUser(auth.userId);
    if (!sender?.handle) throw notFound("User");

    const org = await this.getOrg(auth.orgId);
    if (!org) throw notFound("Org");

    const senderParts = parseUserHandle(sender.handle);
    const fromAgent = await this.resolveAgentForUser(auth.userId, input.from_agent);
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

    if (isOrgBroadcast) {
      // Exclude sender when other members exist; sole-member orgs deliver @all@org to self
      // (default-agent inbox) so founders can still use broadcast before inviting anyone.
      recipientIds = await this.listMemberIds(auth.orgId, auth.userId);
      if (recipientIds.length === 0) {
        recipientIds = [auth.userId];
      }
      audience = broadcastHandle(org.slug);
      isBroadcast = true;
    } else if (isMyAgents) {
      // Bare @all → fan-out to all of the current user's agents (inbox visibility).
      // Crypto still seals once to the user's own device pubkeys.
      const { agents } = await this.listAgents(auth);
      if (agents.length === 0) {
        throw new HubError("No agents registered", "unknown_agent", 400);
      }
      recipientIds = [auth.userId];
      audience = myAgentsHandle();
      isBroadcast = true;
    } else {
      const parsedTo = parseDisplayAddress(trimmedTo);

      if (parsedTo.kind === "self_agent") {
        // @claude → expand to you@org/claude for the authenticated user.
        const toAgent = await this.resolveAgentForUser(auth.userId, parsedTo.agentSlug);
        audience = formatDisplayAddress(senderParts.local, senderParts.orgSlug, toAgent.slug);
        audienceAgentId = toAgent.id;
        audienceWirePath = formatWirePath(senderParts.orgSlug, senderParts.local, toAgent.slug);
        if (fromAgent.id === toAgent.id) {
          throw new HubError(
            `Cannot hand off to the same agent (${fromAgent.slug}). Send to a different agent address, e.g. @claude`,
            "invalid_recipient",
          );
        }
        recipientIds = [auth.userId];
      } else if (parsedTo.kind === "user") {
        const bareTo = formatDisplayAddress(parsedTo.local, parsedTo.orgSlug);
        await this.assertSameOrgHandle(auth.orgId, bareTo);
        const recipient = await this.getUserByHandle(bareTo);
        if (!recipient) throw notFound("Recipient");

        const toAgent = await this.resolveAgentForUser(recipient.id, parsedTo.agentSlug);
        audience = formatDisplayAddress(parsedTo.local, parsedTo.orgSlug, toAgent.slug);
        audienceAgentId = toAgent.id;
        audienceWirePath = formatWirePath(parsedTo.orgSlug, parsedTo.local, toAgent.slug);

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
      } else {
        throw new HubError("Invalid recipient address", "invalid_handle");
      }
    }

    const threadId = crypto.randomUUID();
    const messageId = crypto.randomUUID();
    const ts = nowIso();

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
      created_at: ts,
      updated_at: ts,
    };

    const message: ThreadMessage = {
      id: messageId,
      thread_id: threadId,
      from_user_id: sender.id,
      from_handle: fromDisplay,
      envelope: input.envelope,
      created_at: ts,
    };

    const tx = this.kv.atomic();
    tx.set(this.threadKey(threadId), thread);
    tx.set(this.messageKey(threadId, messageId), message);
    tx.set(this.inboxKey(sender.id, threadId), {
      thread_id: threadId,
      your_status: "replied",
      role: "sender",
      updated_at: ts,
    } satisfies InboxEntry);

    for (const rid of recipientIds) {
      tx.set(this.inboxKey(rid, threadId), {
        thread_id: threadId,
        your_status: "pending",
        role: "recipient",
        updated_at: ts,
      } satisfies InboxEntry);
    }

    const res = await tx.commit();
    if (!res.ok) throw new HubError("Failed to create thread", "internal", 500);

    return { thread, message_id: messageId };
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
      const thread = threadRes.value;
      if (!thread || thread.org_id !== auth.orgId) continue;

      const enriched: ThreadMeta = {
        ...thread,
        your_status: inbox.your_status,
      };

      if (filter === "needs_action") {
        if (inbox.your_status === "pending" && thread.status === "open") {
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
  ): Promise<{ thread: ThreadMeta; messages: ThreadMessage[] }> {
    const inbox = await this.getInboxEntry(auth.userId, threadId);
    if (!inbox) throw forbidden("Not a thread participant");

    const threadRes = await this.kv.get<ThreadMeta>(this.threadKey(threadId));
    const thread = threadRes.value;
    if (!thread || thread.org_id !== auth.orgId) throw notFound("Thread");

    const messages: ThreadMessage[] = [];
    const iter = this.kv.list<ThreadMessage>({ prefix: this.messagesPrefix(threadId) });
    for await (const entry of iter) {
      const msg = entry.value;
      if (this.canViewMessage(auth, thread, inbox, msg)) {
        messages.push(msg);
      }
    }
    messages.sort((a, b) => a.created_at.localeCompare(b.created_at));

    return {
      thread: { ...thread, your_status: inbox.your_status },
      messages,
    };
  }

  async postReply(
    auth: AuthContext,
    threadId: string,
    input: ReplyInput,
  ): Promise<{ message_id: string }> {
    this.assertEnvelopeSize(input.envelope);
    const inbox = await this.getInboxEntry(auth.userId, threadId);
    if (!inbox) throw forbidden("Not a thread participant");

    const threadRes = await this.kv.get<ThreadMeta>(this.threadKey(threadId));
    const thread = threadRes.value;
    if (!thread || thread.org_id !== auth.orgId) throw notFound("Thread");
    if (thread.status === "closed") {
      throw new HubError("Thread is closed", "thread_closed", 409);
    }

    if (inbox.role === "sender" && !input.to_agent?.trim()) {
      throw new HubError(
        "Sender cannot reply on own thread; start a new thread instead",
        "invalid_reply",
        400,
      );
    }

    const user = await this.getUser(auth.userId);
    if (!user?.handle) throw notFound("User");

    const userParts = parseUserHandle(user.handle);
    const fromAgent = await this.resolveAgentForUser(auth.userId, input.from_agent);
    const fromDisplay = formatDisplayAddress(userParts.local, userParts.orgSlug, fromAgent.slug);

    const messageId = crypto.randomUUID();
    const ts = nowIso();

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
      envelope: input.envelope,
      created_at: ts,
      sender_only: thread.kind === "broadcast",
    };

    const tx = this.kv.atomic();
    tx.set(this.messageKey(threadId, messageId), message);
    tx.set(this.threadKey(threadId), updatedThread);
    tx.set(this.inboxKey(auth.userId, threadId), {
      ...inbox,
      your_status: "replied",
      updated_at: ts,
    });
    tx.set(this.inboxKey(thread.from_user_id, threadId), {
      ...(await this.getInboxEntry(thread.from_user_id, threadId) ?? inbox),
      updated_at: ts,
    });
    const res = await tx.commit();
    if (!res.ok) throw new HubError("Failed to post reply", "internal", 500);

    return { message_id: messageId };
  }

  async closeThread(auth: AuthContext, threadId: string): Promise<{ thread: ThreadMeta }> {
    const inbox = await this.getInboxEntry(auth.userId, threadId);
    if (!inbox) throw forbidden("Not a thread participant");

    const threadRes = await this.kv.get<ThreadMeta>(this.threadKey(threadId));
    const thread = threadRes.value;
    if (!thread || thread.org_id !== auth.orgId) throw notFound("Thread");
    if (thread.from_user_id !== auth.userId) {
      throw forbidden("Only the sender can close a thread");
    }
    if (thread.status === "closed") return { thread };

    const updated: ThreadMeta = {
      ...thread,
      status: "closed",
      updated_at: nowIso(),
    };
    await this.kv.set(this.threadKey(threadId), updated);
    return { thread: { ...updated, your_status: inbox.your_status } };
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
    return res.value;
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
    const iter = this.kv.list<string>({ prefix: this.userAgentsPrefix(userId) });
    for await (const entry of iter) {
      const agent = await this.getAgent(entry.value);
      if (agent) rules.push({ match_slug: agent.slug, agent_id: agent.id });
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
   * Resolve agent for address routing.
   * Bare → default agent. Slug → most specific router rule, else slug index.
   * Renamed slugs fail with a clear hint (no silent redirect).
   */
  private async resolveAgentForUser(userId: string, slug?: string): Promise<Agent> {
    const router = await this.loadRouter(userId);

    if (slug?.trim()) {
      const normalized = slug.trim().toLowerCase();

      // Most specific: exact match_slug rule wins.
      const rule = router.rules.find((r) => r.match_slug === normalized);
      if (rule) {
        const agent = await this.getAgent(rule.agent_id);
        if (agent) return agent;
      }

      const mapped = await this.kv.get<string>(this.userAgentSlugKey(userId, normalized));
      if (mapped.value) {
        const agent = await this.getAgent(mapped.value);
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

  async createInviteAsAdmin(auth: AuthContext): Promise<Invite> {
    return this.createInvite(auth);
  }

  async listInvitesAsAdmin(auth: AuthContext): Promise<{ invites: Invite[] }> {
    return this.listInvites(auth);
  }

  async createOrg(slug: string, name?: string): Promise<Org> {
    const normalized = slug.trim().toLowerCase();
    assertValidSlug(normalized);
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
    return new HubStore(kv, createAuth0Verifier({ domain, audience }));
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
