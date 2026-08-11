import { Hono } from "hono";
import type { McpConfig } from "../config.ts";
import {
  bearerTokenFromHeader,
  wwwAuthenticateHeader,
  type TokenVerifier,
  type Auth0Claims,
} from "../auth/oauth.ts";
import { HubClient, HubClientError } from "../hub/client.ts";
import { bindWebSession } from "../session/bind.ts";
import { handleMcpRequest } from "../protocol/handler.ts";
import type { McpRequest } from "../protocol/types.ts";
import {
  globalSessionStore,
  type SessionStore,
  type TransportSession,
} from "../transport/sessions.ts";
import {
  acceptsEventStream,
  acceptsPostMcp,
  openStandaloneSseStream,
} from "../transport/sse.ts";

const SERVER_VERSION = "0.1.0";

/** Protocol versions we negotiate (handler still returns 2024-11-05 in initialize). */
const SUPPORTED_PROTOCOL_VERSIONS = new Set([
  "2024-11-05",
  "2025-03-26",
  "2025-06-18",
  "2025-11-25",
]);

function jsonRpcError(
  status: number,
  message: string,
  code = -32000,
  extraHeaders?: Record<string, string>,
): Response {
  return new Response(
    JSON.stringify({
      jsonrpc: "2.0",
      id: null,
      error: { code, message },
    }),
    {
      status,
      headers: {
        "Content-Type": "application/json",
        ...(extraHeaders ?? {}),
      },
    },
  );
}

function isInitializeRequest(raw: unknown): boolean {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return false;
  const r = raw as McpRequest;
  return r.method === "initialize";
}

function hasJsonRpcRequests(body: unknown): boolean {
  const items = Array.isArray(body) ? body : [body];
  return items.some((raw) => {
    if (!raw || typeof raw !== "object") return false;
    const r = raw as McpRequest;
    return (
      typeof r.method === "string" &&
      !r.method.startsWith("notifications/") &&
      r.id !== undefined &&
      r.id !== null
    );
  });
}

export function createMcpRoutes(
  config: McpConfig,
  verifier: TokenVerifier,
  hub: HubClient,
  options?: { sessions?: SessionStore },
) {
  const routes = new Hono();
  const sessions = options?.sessions ?? globalSessionStore;

  const unauthorized = (
    kind: "missing" | "invalid" = "missing",
    message?: string,
  ) => {
    const isInvalid = kind === "invalid";
    const msg = message ??
      (isInvalid ? "Invalid or expired token" : "Bearer token required");
    return new Response(
      JSON.stringify({
        error: "unauthorized",
        message: msg,
        // ChatGPT surfaces this as "Reauthentication required" on 401.
      }),
      {
        status: 401,
        headers: {
          "Content-Type": "application/json",
          "WWW-Authenticate": wwwAuthenticateHeader(config, {
            error: isInvalid ? "invalid_token" : undefined,
            description: msg,
          }),
        },
      },
    );
  };

  function resolveSlug(c: {
    req: {
      query: (k: string) => string | undefined;
      header: (k: string) => string | undefined;
    };
  }): string {
    const fromQuery = c.req.query("slug")?.trim();
    const fromHeader = c.req.header("X-Mutande-Agent-Slug")?.trim();
    return (fromQuery || fromHeader || config.defaultAgentSlug).toLowerCase();
  }

  async function authenticate(
    authorization: string | undefined,
  ): Promise<{ token: string; claims: Auth0Claims } | Response> {
    const token = bearerTokenFromHeader(authorization);
    if (!token) return unauthorized("missing");
    try {
      const claims = await verifier.verifyAccessToken(token);
      return { token, claims };
    } catch {
      // Wrong aud/iss/exp → ChatGPT reports MCP_ACTION_DISCOVERY_FAILED /
      // "Reauthentication required" after a successful OAuth code exchange.
      return unauthorized("invalid");
    }
  }

  function protocolVersionOk(header: string | undefined): boolean {
    const v = header?.trim() || "2024-11-05";
    return SUPPORTED_PROTOCOL_VERSIONS.has(v);
  }

  /**
   * Resolve transport session from Mcp-Session-Id.
   * - missing + required → 400
   * - present but unknown / wrong user → 404
   */
  function resolveTransportSession(
    sessionHeader: string | undefined,
    claims: Auth0Claims,
    opts: { required: boolean },
  ): TransportSession | undefined | Response {
    const id = sessionHeader?.trim();
    if (!id) {
      if (opts.required) {
        return jsonRpcError(
          400,
          "Bad Request: Mcp-Session-Id header is required",
        );
      }
      return undefined;
    }
    const session = sessions.getForUser(id, claims.sub);
    if (!session) {
      return jsonRpcError(404, "Session not found", -32001);
    }
    return session;
  }

  async function bindOrError(
    c: {
      req: {
        query: (k: string) => string | undefined;
        header: (k: string) => string | undefined;
      };
      json: (body: unknown, status?: number) => Response;
    },
    token: string,
    claims: Auth0Claims,
  ) {
    const slug = resolveSlug(c);
    try {
      return await bindWebSession(hub, token, claims, slug);
    } catch (e) {
      if (e instanceof HubClientError && e.status === 401) {
        // Hub rejected the same Bearer (usually missing AUTH0_MCP_AUDIENCE on hub).
        return unauthorized(
          "invalid",
          "Hub rejected access token (check AUTH0_MCP_AUDIENCE on hub)",
        );
      }
      if (e instanceof HubClientError && e.status === 403) {
        return c.json(
          { error: "onboarding_required", message: e.message },
          403,
        );
      }
      const message = e instanceof Error ? e.message : "session bind failed";
      const status = message.toLowerCase().includes("onboarding") ? 403 : 502;
      return c.json({ error: "bind_failed", message }, status);
    }
  }

  // --- GET /mcp — open standalone SSE stream (Streamable HTTP) ---
  routes.get("/mcp", async (c) => {
    const auth = await authenticate(c.req.header("Authorization"));
    if (auth instanceof Response) return auth;

    if (!acceptsEventStream(c.req.header("Accept"))) {
      return jsonRpcError(
        406,
        "Not Acceptable: Client must accept text/event-stream",
      );
    }

    if (!protocolVersionOk(c.req.header("Mcp-Protocol-Version"))) {
      return jsonRpcError(
        400,
        `Bad Request: Unsupported protocol version (supported: ${[
          ...SUPPORTED_PROTOCOL_VERSIONS,
        ].join(", ")})`,
      );
    }

    // Session optional on GET if client has not initialized yet; when provided, must be valid.
    const transport = resolveTransportSession(
      c.req.header("Mcp-Session-Id"),
      auth.claims,
      { required: false },
    );
    if (transport instanceof Response) return transport;

    if (transport?.sse) {
      return jsonRpcError(
        409,
        "Conflict: Only one SSE stream is allowed per session",
      );
    }

    // Ensure token still maps to an onboarded user (no hub payload leaked on stream).
    const bound = await bindOrError(c, auth.token, auth.claims);
    if (bound instanceof Response) return bound;

    // If client had no session yet, mint one so DELETE/reconnect can target it.
    let sessionId = transport?.id;
    if (!sessionId) {
      const created = sessions.create(auth.claims.sub, bound.slug);
      sessionId = created.id;
    }

    return openStandaloneSseStream({
      sessionId,
      store: sessions,
      headers: {
        "Mcp-Session-Id": sessionId,
      },
    });
  });

  // --- DELETE /mcp — terminate session ---
  routes.delete("/mcp", async (c) => {
    const auth = await authenticate(c.req.header("Authorization"));
    if (auth instanceof Response) return auth;

    if (!protocolVersionOk(c.req.header("Mcp-Protocol-Version"))) {
      return jsonRpcError(
        400,
        `Bad Request: Unsupported protocol version (supported: ${[
          ...SUPPORTED_PROTOCOL_VERSIONS,
        ].join(", ")})`,
      );
    }

    const transport = resolveTransportSession(
      c.req.header("Mcp-Session-Id"),
      auth.claims,
      { required: true },
    );
    if (transport instanceof Response) return transport;
    if (!transport) {
      return jsonRpcError(400, "Bad Request: Mcp-Session-Id header is required");
    }

    sessions.delete(transport.id);
    return new Response(null, { status: 200 });
  });

  // --- POST /mcp — JSON-RPC (application/json response; Streamable HTTP) ---
  routes.post("/mcp", async (c) => {
    if (!acceptsPostMcp(c.req.header("Accept"))) {
      return jsonRpcError(
        406,
        "Not Acceptable: Client must accept both application/json and text/event-stream",
      );
    }

    const contentType = c.req.header("Content-Type") ?? "";
    if (contentType && !contentType.includes("application/json")) {
      return jsonRpcError(
        415,
        "Unsupported Media Type: Content-Type must be application/json",
      );
    }

    const auth = await authenticate(c.req.header("Authorization"));
    if (auth instanceof Response) return auth;

    let body: unknown;
    try {
      body = await c.req.json();
    } catch {
      return c.json(
        {
          jsonrpc: "2.0",
          id: null,
          error: { code: -32700, message: "parse error" },
        },
        400,
      );
    }

    const initReq = Array.isArray(body)
      ? body.some(isInitializeRequest)
      : isInitializeRequest(body);

    let transportSession: TransportSession | undefined;
    if (initReq) {
      if (Array.isArray(body) && body.length > 1) {
        return jsonRpcError(
          400,
          "Invalid Request: Only one initialization request is allowed",
          -32600,
        );
      }
      // New transport session on initialize (ignore stale client session id).
      transportSession = sessions.create(
        auth.claims.sub,
        resolveSlug(c),
      );
    } else {
      const resolved = resolveTransportSession(
        c.req.header("Mcp-Session-Id"),
        auth.claims,
        // Soft: require only when client sent one; allow legacy one-shot POSTs.
        { required: false },
      );
      if (resolved instanceof Response) return resolved;
      transportSession = resolved;

      if (
        c.req.header("Mcp-Protocol-Version") &&
        !protocolVersionOk(c.req.header("Mcp-Protocol-Version"))
      ) {
        return jsonRpcError(
          400,
          `Bad Request: Unsupported protocol version (supported: ${[
            ...SUPPORTED_PROTOCOL_VERSIONS,
          ].join(", ")})`,
        );
      }
    }

    const bound = await bindOrError(c, auth.token, auth.claims);
    if (bound instanceof Response) return bound;

    if (!hasJsonRpcRequests(body)) {
      // Notifications / responses only → 202 Accepted.
      const headers: Record<string, string> = {};
      if (transportSession) headers["Mcp-Session-Id"] = transportSession.id;
      return new Response(null, { status: 202, headers });
    }

    const requests = Array.isArray(body) ? body : [body];
    const responses = [];
    for (const raw of requests) {
      const req = raw as McpRequest;
      if (!req || typeof req.method !== "string") {
        responses.push({
          jsonrpc: "2.0",
          id: null,
          error: { code: -32600, message: "invalid request" },
        });
        continue;
      }
      const res = await handleMcpRequest(req, {
        session: bound,
        serverVersion: SERVER_VERSION,
        hub,
      });
      if (res) responses.push(res);
    }

    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (transportSession) headers["Mcp-Session-Id"] = transportSession.id;

    if (Array.isArray(body)) {
      return new Response(JSON.stringify(responses), { status: 200, headers });
    }
    if (responses.length === 0) {
      return new Response(null, { status: 202, headers });
    }
    return new Response(JSON.stringify(responses[0]), { status: 200, headers });
  });

  // Other methods → 405 with Allow.
  routes.all("/mcp", (c) => {
    if (c.req.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          Allow: "GET, POST, DELETE, OPTIONS",
          "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
          "Access-Control-Allow-Headers":
            "Authorization, Content-Type, Accept, Mcp-Session-Id, Mcp-Protocol-Version, X-Mutande-Agent-Slug",
          "Access-Control-Expose-Headers": "Mcp-Session-Id",
        },
      });
    }
    return jsonRpcError(405, "Method not allowed.", -32000, {
      Allow: "GET, POST, DELETE, OPTIONS",
    });
  });

  return routes;
}
