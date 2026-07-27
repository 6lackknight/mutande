import {
  envelopeTooLarge,
  forbidden,
  HubError,
  notFound,
  conflict,
  quotaExceeded,
} from "./errors.ts";
import { randomToken, signJwt, verifyJwt } from "./jwt.ts";
import type {
  AuthContext,
  BlobMeta,
  Contact,
  CreateThreadInput,
  Draft,
  Envelope,
  InboxEntry,
  Invite,
  Org,
  RegisterInput,
  ReplyInput,
  ThreadFilter,
  ThreadMessage,
  ThreadMeta,
  User,
} from "./types.ts";
import { createBlobUrls } from "./r2.ts";
import {
  MAX_ENVELOPE_BYTES,
  ORG_BLOB_QUOTA_BYTES,
} from "./types.ts";

function nowIso(): string {
  return new Date().toISOString();
}

function parseHandle(handle: string): { local: string; orgSlug: string } {
  const at = handle.lastIndexOf("@");
  if (at <= 0 || at === handle.length - 1) {
    throw new HubError("Invalid handle format", "invalid_handle");
  }
  return { local: handle.slice(0, at), orgSlug: handle.slice(at + 1) };
}

function broadcastHandle(orgSlug: string): string {
  return `@all@${orgSlug}`;
}

export class HubStore {
  constructor(
    private readonly kv: Deno.Kv,
    readonly jwtSecret: string,
  ) {}

  // --- Key helpers ---

  private userKey(id: string) {
    return ["users", id];
  }
  private handleKey(handle: string) {
    return ["handles", handle];
  }
  private orgKey(id: string) {
    return ["orgs", id];
  }
  private orgSlugKey(slug: string) {
    return ["org_slugs", slug];
  }
  private memberKey(orgId: string, userId: string) {
    return ["org_members", orgId, userId];
  }
  private membersPrefix(orgId: string) {
    return ["org_members", orgId];
  }
  private inviteKey(code: string) {
    return ["invites", code];
  }
  private threadKey(id: string) {
    return ["threads", id];
  }
  private inboxKey(userId: string, threadId: string) {
    return ["inbox", userId, threadId];
  }
  private inboxPrefix(userId: string) {
    return ["inbox", userId];
  }
  private messageKey(threadId: string, messageId: string) {
    return ["messages", threadId, messageId];
  }
  private messagesPrefix(threadId: string) {
    return ["messages", threadId];
  }
  private draftKey(userId: string, draftId: string) {
    return ["drafts", userId, draftId];
  }
  private draftsPrefix(userId: string) {
    return ["drafts", userId];
  }
  private blobKey(id: string) {
    return ["blobs", id];
  }
  private orgQuotaKey(orgId: string) {
    return ["org_blob_quota", orgId];
  }
  private refreshKey(token: string) {
    return ["refresh_tokens", token];
  }

  // --- Envelope validation ---

  assertEnvelopeSize(envelope: Envelope): void {
    const size = new TextEncoder().encode(JSON.stringify(envelope)).byteLength;
    if (size > MAX_ENVELOPE_BYTES) throw envelopeTooLarge(size);
  }

  // --- Invites (bootstrap / admin) ---

  async createInvite(orgId: string): Promise<Invite> {
    const org = await this.getOrg(orgId);
    if (!org) throw notFound("Org");
    const invite: Invite = {
      code: randomToken(),
      org_id: orgId,
      created_at: nowIso(),
    };
    await this.kv.set(this.inviteKey(invite.code), invite);
    return invite;
  }

  async createOrg(slug: string): Promise<Org> {
    const existing = await this.kv.get<Org>(this.orgSlugKey(slug));
    if (existing.value) throw conflict(`Org slug '${slug}' already exists`);
    const org: Org = { id: crypto.randomUUID(), slug, created_at: nowIso() };
    const tx = this.kv.atomic();
    tx.set(this.orgKey(org.id), org);
    tx.set(this.orgSlugKey(slug), org);
    tx.set(this.orgQuotaKey(org.id), 0);
    const res = await tx.commit();
    if (!res.ok) throw new HubError("Failed to create org", "internal", 500);
    return org;
  }

  // --- Auth ---

  async register(input: RegisterInput): Promise<{
    user: User;
    access_token: string;
    refresh_token: string;
  }> {
    const inviteRes = await this.kv.get<Invite>(this.inviteKey(input.invite_code));
    const invite = inviteRes.value;
    if (!invite) throw notFound("Invite");
    if (invite.used_by) throw conflict("Invite already used");

    const { local, orgSlug } = parseHandle(input.handle);
    if (local.toLowerCase() === "@all" || input.handle.toLowerCase().startsWith("@all@")) {
      throw new HubError("Handle cannot use @all broadcast prefix", "invalid_handle");
    }
    const orgRes = await this.kv.get<Org>(this.orgSlugKey(orgSlug));
    const org = orgRes.value;
    if (!org || org.id !== invite.org_id) {
      throw forbidden("Handle must belong to invite org");
    }

    const handleTaken = await this.kv.get(this.handleKey(input.handle));
    if (handleTaken.value) throw conflict("Handle already registered");

    const user: User = {
      id: crypto.randomUUID(),
      handle: input.handle,
      org_id: org.id,
      pubkey: input.pubkey,
      created_at: nowIso(),
    };

    const refreshToken = randomToken();
    const usedInvite: Invite = { ...invite, used_by: user.id };

    const tx = this.kv.atomic();
    tx.check(inviteRes).check(handleTaken);
    tx.set(this.userKey(user.id), user);
    tx.set(this.handleKey(user.handle), user.id);
    tx.set(this.memberKey(org.id, user.id), user.id);
    tx.set(this.inviteKey(invite.code), usedInvite);
    tx.set(this.refreshKey(refreshToken), {
      user_id: user.id,
      created_at: nowIso(),
    });
    const res = await tx.commit();
    if (!res.ok) throw conflict("Registration conflict");

    const accessToken = await signJwt(
      { sub: user.id, org_id: user.org_id, handle: user.handle },
      this.jwtSecret,
    );

    return { user, access_token: accessToken, refresh_token: refreshToken };
  }

  async refreshToken(refreshToken: string): Promise<{ access_token: string }> {
    const res = await this.kv.get<{ user_id: string }>(this.refreshKey(refreshToken));
    if (!res.value) throw forbidden("Invalid refresh token");
    const user = await this.getUser(res.value.user_id);
    if (!user) throw notFound("User");
    const accessToken = await signJwt(
      { sub: user.id, org_id: user.org_id, handle: user.handle },
      this.jwtSecret,
    );
    return { access_token: accessToken };
  }

  async getMe(userId: string): Promise<User> {
    const user = await this.getUser(userId);
    if (!user) throw notFound("User");
    return user;
  }

  authFromJwt(payload: Record<string, unknown>): AuthContext {
    const userId = payload.sub;
    const orgId = payload.org_id;
    const handle = payload.handle;
    if (typeof userId !== "string" || typeof orgId !== "string" || typeof handle !== "string") {
      throw forbidden("Invalid token claims");
    }
    return { userId, orgId, handle };
  }

  async verifyAccessToken(token: string): Promise<AuthContext> {
    const payload = await verifyJwt(token, this.jwtSecret);
    return this.authFromJwt(payload);
  }

  // --- Contacts ---

  async listContacts(auth: AuthContext): Promise<{ contacts: Contact[] }> {
    const org = await this.getOrg(auth.orgId);
    if (!org) throw notFound("Org");

    const contacts: Contact[] = [{ handle: broadcastHandle(org.slug), pubkey: null }];
    const iter = this.kv.list<string>({ prefix: this.membersPrefix(auth.orgId) });
    for await (const entry of iter) {
      const memberId = entry.value;
      if (memberId === auth.userId) continue;
      const user = await this.getUser(memberId);
      if (user) contacts.push({ handle: user.handle, pubkey: user.pubkey });
    }
    contacts.sort((a, b) => a.handle.localeCompare(b.handle));
    return { contacts };
  }

  // --- Threads ---

  async createThread(auth: AuthContext, input: CreateThreadInput): Promise<{
    thread: ThreadMeta;
    message_id: string;
  }> {
    this.assertEnvelopeSize(input.envelope);
    const sender = await this.getUser(auth.userId);
    if (!sender) throw notFound("User");

    const org = await this.getOrg(auth.orgId);
    if (!org) throw notFound("Org");

    const isBroadcast = input.to === broadcastHandle(org.slug);
    let recipientIds: string[] = [];
    let audience = input.to;

    if (isBroadcast) {
      recipientIds = await this.listMemberIds(auth.orgId, auth.userId);
    } else {
      await this.assertSameOrgHandle(auth.orgId, input.to);
      const recipient = await this.getUserByHandle(input.to);
      if (!recipient) throw notFound("Recipient");
      if (recipient.id === auth.userId) {
        throw new HubError("Cannot message yourself", "invalid_recipient");
      }
      recipientIds = [recipient.id];
    }

    const threadId = crypto.randomUUID();
    const messageId = crypto.randomUUID();
    const ts = nowIso();

    const thread: ThreadMeta = {
      id: threadId,
      kind: isBroadcast ? "broadcast" : "direct",
      status: "open",
      from: sender.handle,
      from_user_id: sender.id,
      audience,
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
      from_handle: sender.handle,
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
      } as ThreadMeta & { your_status: string };

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
      thread: { ...thread, your_status: inbox.your_status } as ThreadMeta,
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

    const user = await this.getUser(auth.userId);
    if (!user) throw notFound("User");

    const isSender = inbox.role === "sender";
    if (isSender) {
      throw new HubError(
        "Sender cannot reply on own thread; start a new thread instead",
        "invalid_reply",
        400,
      );
    }

    const messageId = crypto.randomUUID();
    const ts = nowIso();
    const message: ThreadMessage = {
      id: messageId,
      thread_id: threadId,
      from_user_id: user.id,
      from_handle: user.handle,
      envelope: input.envelope,
      created_at: ts,
      sender_only: thread.kind === "broadcast",
    };

    const updatedThread: ThreadMeta = {
      ...thread,
      reply_count: thread.reply_count + 1,
      updated_at: ts,
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
    return { thread: { ...updated, your_status: inbox.your_status } as ThreadMeta };
  }

  // --- Drafts ---

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

  // --- Blobs ---

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
    // Org-wide ACL: any member may download any org blob by id (narrower ACL later).
    if (meta.org_id !== auth.orgId) throw forbidden("Blob belongs to another org");

    const { url, expires_at } = await createBlobUrls(blobId, "GET");
    return {
      download_url: url,
      expires_at,
      meta,
    };
  }

  // --- Internal helpers ---

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

  private async assertSameOrgHandle(orgId: string, handle: string): Promise<void> {
    const { orgSlug } = parseHandle(handle);
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

}

export function createStore(kv: Deno.Kv, jwtSecret?: string): HubStore {
  const envSecret = jwtSecret ?? Deno.env.get("JWT_SECRET");
  if (Deno.env.get("DENO_DEPLOYMENT_ID") && !envSecret) {
    throw new Error("JWT_SECRET must be set in production");
  }
  const secret = envSecret ?? "dev-secret-change-me";
  return new HubStore(kv, secret);
}
