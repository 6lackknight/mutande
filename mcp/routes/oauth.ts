import { Hono } from "hono";
import type { McpConfig } from "../config.ts";
import { protectedResourceMetadata } from "../auth/oauth.ts";

/**
 * OAuth discovery for MCP clients (ChatGPT web / Claude.ai).
 * Auth0 is the authorization server; this service is the resource server.
 */
export function createOauthRoutes(config: McpConfig) {
  const routes = new Hono();

  routes.get("/.well-known/oauth-protected-resource", (c) => {
    return c.json(protectedResourceMetadata(config));
  });

  // Some clients probe path-suffixed PRM (RFC 9728 §3).
  routes.get("/.well-known/oauth-protected-resource/*", (c) => {
    return c.json(protectedResourceMetadata(config));
  });

  // Convenience: point at Auth0 AS metadata (clients should fetch Auth0 directly).
  routes.get("/.well-known/oauth-authorization-server", (c) => {
    const issuer = `https://${config.auth0Domain}/`;
    return c.redirect(
      `${issuer}.well-known/oauth-authorization-server`,
      307,
    );
  });

  return routes;
}
