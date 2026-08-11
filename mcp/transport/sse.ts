/**
 * Streamable HTTP SSE helpers (MCP 2025-03-26 transport).
 * GET opens a long-lived event stream; keepalives prevent proxy idle timeouts.
 */

import {
  encodeSseComment,
  type SessionStore,
} from "./sessions.ts";

export const SSE_HEADERS: Record<string, string> = {
  "Content-Type": "text/event-stream",
  "Cache-Control": "no-cache, no-transform",
  Connection: "keep-alive",
  // Disable nginx/cloudflare buffering when present.
  "X-Accel-Buffering": "no",
};

const KEEPALIVE_MS = 15_000;

export interface OpenSseOptions {
  sessionId?: string;
  store?: SessionStore;
  /** Extra response headers (e.g. Mcp-Session-Id). */
  headers?: Record<string, string>;
}

/**
 * Open a standalone GET SSE stream.
 * Sends an immediate comment so clients/proxies see bytes right away.
 */
export function openStandaloneSseStream(options: OpenSseOptions = {}): Response {
  const { sessionId, store } = options;
  let keepalive: number | undefined;
  let closed = false;

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const cancel = () => {
        if (closed) return;
        closed = true;
        if (keepalive !== undefined) clearInterval(keepalive);
        if (sessionId && store) store.detachSse(sessionId);
        try {
          controller.close();
        } catch {
          /* already closed */
        }
      };

      if (sessionId && store) {
        const ok = store.attachSse(sessionId, controller, cancel);
        if (!ok) {
          controller.error(new Error("sse_conflict"));
          return;
        }
      }

      try {
        controller.enqueue(encodeSseComment("connected"));
      } catch {
        cancel();
        return;
      }

      keepalive = setInterval(() => {
        try {
          controller.enqueue(encodeSseComment("keepalive"));
        } catch {
          cancel();
        }
      }, KEEPALIVE_MS);
    },
    cancel() {
      if (keepalive !== undefined) clearInterval(keepalive);
      if (sessionId && store) store.detachSse(sessionId);
      closed = true;
    },
  });

  const headers: Record<string, string> = {
    ...SSE_HEADERS,
    ...(options.headers ?? {}),
  };
  if (sessionId) headers["Mcp-Session-Id"] = sessionId;

  return new Response(stream, { status: 200, headers });
}

/** Accept header includes text/event-stream (GET requirement). */
export function acceptsEventStream(accept: string | undefined): boolean {
  if (!accept) return false;
  return accept.includes("text/event-stream") || accept.includes("*/*");
}

/**
 * POST clients MUST list both application/json and text/event-stream.
 * Missing Accept is tolerated for curl / older probes (JSON response path).
 */
export function acceptsPostMcp(accept: string | undefined): boolean {
  if (!accept || accept.trim() === "" || accept.includes("*/*")) return true;
  return (
    accept.includes("application/json") && accept.includes("text/event-stream")
  );
}
