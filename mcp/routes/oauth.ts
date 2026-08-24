import { Hono } from "hono";
import type { Context } from "hono";
import type { McpConfig } from "../config.ts";
import {
  authorizationServerMetadata,
  protectedResourceMetadata,
  resourceFromPrmPath,
} from "../auth/oauth.ts";

/**
 * OAuth discovery for MCP clients (ChatGPT web / Claude.ai / Grok Bot).
 * Auth0 is the authorization server; this service is the resource server.
 */
export function createOauthRoutes(config: McpConfig) {
  const routes = new Hono();
  const prm = (path: string) =>
    protectedResourceMetadata(
      config,
      resourceFromPrmPath(config.publicUrl, path),
    );
  const as = () => authorizationServerMetadata(config);

  const json = (c: Context, body: unknown) => {
    const res = c.json(body);
    res.headers.set("Access-Control-Allow-Origin", "*");
    return res;
  };

  routes.get("/.well-known/oauth-protected-resource", (c) => {
    return json(c, prm(c.req.path));
  });

  // RFC 9728 §3 path insertion (e.g. …/oauth-protected-resource/mcp).
  routes.get("/.well-known/oauth-protected-resource/*", (c) => {
    return json(c, prm(c.req.path));
  });

  // Loaders that append well-known onto the connector URL (/mcp).
  routes.get("/mcp/.well-known/oauth-protected-resource", (c) => {
    return json(c, prm(c.req.path));
  });

  routes.get("/.well-known/oauth-authorization-server", (c) => json(c, as()));
  routes.get("/.well-known/oauth-authorization-server/*", (c) => json(c, as()));
  routes.get("/mcp/.well-known/oauth-authorization-server", (c) => json(c, as()));

  // OIDC discovery fallback used by some MCP OAuth clients.
  routes.get("/.well-known/openid-configuration", (c) => json(c, as()));
  routes.get("/.well-known/openid-configuration/*", (c) => json(c, as()));
  routes.get("/mcp/.well-known/openid-configuration", (c) => json(c, as()));

  // OpenAI plugin domain verification. Token only — no JSON wrapper.
  routes.get("/.well-known/openai-apps-challenge", (c) => {
    const token = config.openaiAppsChallenge;
    if (!token) return c.body(null, 404);
    return c.text(token);
  });

  return routes;
}
