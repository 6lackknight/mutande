/** In-memory MCP Streamable HTTP session registry (per isolate). */

export interface TransportSession {
  id: string;
  /** Auth0 sub that owns this session — rejects cross-user reuse. */
  auth0Sub: string;
  agentSlug: string;
  createdAt: number;
  /** Active GET SSE stream controller, if any. */
  sse?: {
    controller: ReadableStreamDefaultController<Uint8Array>;
    cancel: () => void;
  };
}

const SESSION_TTL_MS = 24 * 60 * 60 * 1000;

export class SessionStore {
  private readonly sessions = new Map<string, TransportSession>();

  create(auth0Sub: string, agentSlug: string): TransportSession {
    this.gc();
    const id = crypto.randomUUID();
    const session: TransportSession = {
      id,
      auth0Sub,
      agentSlug,
      createdAt: Date.now(),
    };
    this.sessions.set(id, session);
    return session;
  }

  get(id: string): TransportSession | undefined {
    const s = this.sessions.get(id);
    if (!s) return undefined;
    if (Date.now() - s.createdAt > SESSION_TTL_MS) {
      this.delete(id);
      return undefined;
    }
    return s;
  }

  /** Validate session id belongs to this Auth0 user. */
  getForUser(id: string, auth0Sub: string): TransportSession | undefined {
    const s = this.get(id);
    if (!s || s.auth0Sub !== auth0Sub) return undefined;
    return s;
  }

  delete(id: string): boolean {
    const s = this.sessions.get(id);
    if (!s) return false;
    s.sse?.cancel();
    this.sessions.delete(id);
    return true;
  }

  attachSse(
    id: string,
    controller: ReadableStreamDefaultController<Uint8Array>,
    cancel: () => void,
  ): boolean {
    const s = this.sessions.get(id);
    if (!s) return false;
    if (s.sse) {
      // Only one standalone GET SSE stream per session (spec / SDK).
      return false;
    }
    s.sse = { controller, cancel };
    return true;
  }

  detachSse(id: string): void {
    const s = this.sessions.get(id);
    if (s) s.sse = undefined;
  }

  /** Best-effort push to the GET SSE stream (server→client notifications). */
  sendSse(id: string, payload: unknown, eventId?: string): boolean {
    const s = this.sessions.get(id);
    if (!s?.sse) return false;
    try {
      s.sse.controller.enqueue(encodeSseMessage(payload, eventId));
      return true;
    } catch {
      this.detachSse(id);
      return false;
    }
  }

  private gc(): void {
    const now = Date.now();
    for (const [id, s] of this.sessions) {
      if (now - s.createdAt > SESSION_TTL_MS) {
        s.sse?.cancel();
        this.sessions.delete(id);
      }
    }
  }
}

/** Shared process-wide store (Deno Deploy: per isolate; clients re-init on 404). */
export const globalSessionStore = new SessionStore();

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
