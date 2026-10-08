/**
 * MCP Streamable HTTP session registry.
 *
 * Durable fields (id, auth0Sub, agentSlug, createdAt) live in Deno KV so any
 * Deploy isolate can resume after recycle. SSE stream controllers stay
 * in-memory on this isolate only — clients reopen GET SSE with the same id.
 */

export interface TransportSession {
  id: string;
  /** Auth0 sub that owns this session — rejects cross-user reuse. */
  auth0Sub: string;
  agentSlug: string;
  createdAt: number;
  /** Active GET SSE stream controller, if any (this isolate only). */
  sse?: {
    controller: ReadableStreamDefaultController<Uint8Array>;
    cancel: () => void;
  };
}

/** Persisted row under `["mcp_sessions", id]` — no tokens, no SSE handles. */
export interface PersistedTransportSession {
  id: string;
  auth0Sub: string;
  agentSlug: string;
  createdAt: number;
}

export const SESSION_TTL_MS = 24 * 60 * 60 * 1000;

export function mcpSessionKey(id: string): Deno.KvKey {
  return ["mcp_sessions", id];
}

export class SessionStore {
  /** Local hydrate + SSE attachments (per isolate). */
  private readonly local = new Map<string, TransportSession>();
  private readonly kv: Deno.Kv | null;

  constructor(kv?: Deno.Kv | null) {
    this.kv = kv ?? null;
  }

  async create(auth0Sub: string, agentSlug: string): Promise<TransportSession> {
    this.gcLocal();
    const id = crypto.randomUUID();
    const createdAt = Date.now();
    const session: TransportSession = {
      id,
      auth0Sub,
      agentSlug,
      createdAt,
    };
    this.local.set(id, session);
    await this.persist(session);
    return session;
  }

  async get(id: string): Promise<TransportSession | undefined> {
    if (this.kv) {
      const row = await this.kv.get<PersistedTransportSession>(
        mcpSessionKey(id),
      );
      const persisted = row.value;
      if (!persisted) {
        // Deleted or expired on another isolate — drop local SSE too.
        const stale = this.local.get(id);
        if (stale) {
          stale.sse?.cancel();
          this.local.delete(id);
        }
        return undefined;
      }
      if (Date.now() - persisted.createdAt > SESSION_TTL_MS) {
        await this.delete(id);
        return undefined;
      }
      let local = this.local.get(id);
      if (!local) {
        local = {
          id: persisted.id,
          auth0Sub: persisted.auth0Sub,
          agentSlug: persisted.agentSlug,
          createdAt: persisted.createdAt,
        };
        this.local.set(id, local);
      } else {
        local.auth0Sub = persisted.auth0Sub;
        local.agentSlug = persisted.agentSlug;
        local.createdAt = persisted.createdAt;
      }
      return local;
    }

    const local = this.local.get(id);
    if (!local) return undefined;
    if (Date.now() - local.createdAt > SESSION_TTL_MS) {
      await this.delete(id);
      return undefined;
    }
    return local;
  }

  /** Validate session id belongs to this Auth0 user. */
  async getForUser(
    id: string,
    auth0Sub: string,
  ): Promise<TransportSession | undefined> {
    const s = await this.get(id);
    if (!s || s.auth0Sub !== auth0Sub) return undefined;
    return s;
  }

  async delete(id: string): Promise<boolean> {
    const hadLocal = this.local.has(id);
    const local = this.local.get(id);
    if (local) {
      local.sse?.cancel();
      this.local.delete(id);
    }
    let hadKv = false;
    if (this.kv) {
      const row = await this.kv.get(mcpSessionKey(id));
      hadKv = row.value != null;
      if (hadKv) await this.kv.delete(mcpSessionKey(id));
    }
    return hadLocal || hadKv;
  }

  attachSse(
    id: string,
    controller: ReadableStreamDefaultController<Uint8Array>,
    cancel: () => void,
  ): boolean {
    const s = this.local.get(id);
    if (!s) return false;
    if (s.sse) {
      // Only one standalone GET SSE stream per session (spec / SDK).
      return false;
    }
    s.sse = { controller, cancel };
    return true;
  }

  detachSse(id: string): void {
    const s = this.local.get(id);
    if (s) s.sse = undefined;
  }

  /** Best-effort push to the GET SSE stream (server→client notifications). */
  sendSse(id: string, payload: unknown, eventId?: string): boolean {
    const s = this.local.get(id);
    if (!s?.sse) return false;
    try {
      s.sse.controller.enqueue(encodeSseMessage(payload, eventId));
      return true;
    } catch {
      this.detachSse(id);
      return false;
    }
  }

  private async persist(session: TransportSession): Promise<void> {
    if (!this.kv) return;
    const row: PersistedTransportSession = {
      id: session.id,
      auth0Sub: session.auth0Sub,
      agentSlug: session.agentSlug,
      createdAt: session.createdAt,
    };
    await this.kv.set(mcpSessionKey(session.id), row, {
      expireIn: SESSION_TTL_MS,
    });
  }

  private gcLocal(): void {
    const now = Date.now();
    for (const [id, s] of this.local) {
      if (now - s.createdAt > SESSION_TTL_MS) {
        s.sse?.cancel();
        this.local.delete(id);
      }
    }
  }
}

/**
 * Process-wide store. Call {@link initGlobalSessionStore} from main before serve
 * so Deploy isolates share session ids via Deno KV.
 */
export let globalSessionStore = new SessionStore(null);

export async function initGlobalSessionStore(
  kv?: Deno.Kv,
): Promise<SessionStore> {
  const resolved = kv ?? await Deno.openKv();
  globalSessionStore = new SessionStore(resolved);
  return globalSessionStore;
}

const textEncoder = new TextEncoder();

export function encodeSseMessage(
  payload: unknown,
  eventId?: string,
): Uint8Array {
  let chunk = "event: message\n";
  if (eventId) chunk += `id: ${eventId}\n`;
  chunk += `data: ${JSON.stringify(payload)}\n\n`;
  return textEncoder.encode(chunk);
}

export function encodeSseComment(comment: string): Uint8Array {
  return textEncoder.encode(`: ${comment}\n\n`);
}
