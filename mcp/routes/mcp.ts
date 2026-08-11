import { Hono } from "hono";
import type { McpConfig } from "../config.ts";
import {
  bearerTokenFromHeader,
  wwwAuthenticateHeader,
  type TokenVerifier,
} from "../auth/oauth.ts";
import { HubClient, HubClientError } from "../hub/client.ts";
import { bindWebSession } from "../session/bind.ts";
import { handleMcpRequest } from "../protocol/handler.ts";
import type { McpRequest } from "../protocol/types.ts";

const SERVER_VERSION = "0.1.0";

export function createMcpRoutes(
  config: McpConfig,
  verifier: TokenVerifier,
  hub: HubClient,
) {
  const routes = new Hono();

  const unauthorized = () =>
    new Response(JSON.stringify({ error: "unauthorized", message: "Bearer token required" }), {
      status: 401,
      headers: {
        "Content-Type": "application/json",
        "WWW-Authenticate": wwwAuthenticateHeader(config),
      },
    });

  /** Resolve agent slug: query ?slug= / header / default. */
  function resolveSlug(c: { req: { query: (k: string) => string | undefined; header: (k: string) => string | undefined } }): string {
    const fromQuery = c.req.query("slug")?.trim();
    const fromHeader = c.req.header("X-Mutande-Agent-Slug")?.trim();
    return (fromQuery || fromHeader || config.defaultAgentSlug).toLowerCase();
  }

  routes.all("/mcp", async (c) => {
    if (c.req.method === "GET") {
      // Streamable HTTP may use GET for SSE; L0 returns 405 with hint.
      return c.json(
        {
          error: "method_not_allowed",
          message:
            "L0 scaffold: POST JSON-RPC to /mcp with Authorization: Bearer <Auth0 access token>. SSE wake is future work.",
        },
        405,
      );
    }

    if (c.req.method !== "POST") {
      return c.json({ error: "method_not_allowed" }, 405);
    }

    const token = bearerTokenFromHeader(c.req.header("Authorization"));
    if (!token) return unauthorized();

    let claims;
    try {
      claims = await verifier.verifyAccessToken(token);
    } catch {
      return unauthorized();
    }

    const slug = resolveSlug(c);
    let session;
    try {
      session = await bindWebSession(hub, token, claims, slug);
    } catch (e) {
      if (e instanceof HubClientError && e.status === 401) {
        return unauthorized();
      }
      if (e instanceof HubClientError && e.status === 403) {
        return c.json(
          {
            error: "onboarding_required",
            message: e.message,
          },
          403,
        );
      }
      const message = e instanceof Error ? e.message : "session bind failed";
      const status = message.toLowerCase().includes("onboarding") ? 403 : 502;
      return c.json({ error: "bind_failed", message }, status);
    }

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

    // Batch (array) or single request.
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
        session,
        serverVersion: SERVER_VERSION,
        hub,
      });
      if (res) responses.push(res);
    }

    if (Array.isArray(body)) {
      return c.json(responses);
    }
    if (responses.length === 0) {
      return new Response(null, { status: 202 });
    }
    return c.json(responses[0]);
  });

  return routes;
}
