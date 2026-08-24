import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import { forbidden } from "../store/errors.ts";
import { isMcpConnectorToken } from "../store/mcp_connectors.ts";
import type { HubStore } from "../store/store.ts";
import type { MintMcpConnectorInput } from "../store/mcp_connectors.ts";

function bearerToken(c: { req: { header: (k: string) => string | undefined } }): string {
  const header = c.req.header("Authorization") ?? "";
  return header.startsWith("Bearer ") ? header.slice("Bearer ".length).trim() : "";
}

function requireAuth0Jwt(c: { req: { header: (k: string) => string | undefined } }) {
  if (isMcpConnectorToken(bearerToken(c))) {
    throw forbidden("Use an Auth0 access token to manage connector keys");
  }
}

export function createMcpConnectorRoutes(store: HubStore) {
  const routes = new Hono<HubEnv>();
  routes.use("*", authMiddleware(store));

  routes.post("/", async (c) => {
    requireAuth0Jwt(c);
    const body = await c.req.json<MintMcpConnectorInput>().catch(() => ({}));
    const minted = await store.mintMcpConnector(c.get("auth"), body ?? {});
    return c.json(minted, 201);
  });

  routes.get("/", async (c) => {
    requireAuth0Jwt(c);
    return c.json(await store.listMcpConnectors(c.get("auth")));
  });

  routes.get("/current", async (c) => {
    const token = bearerToken(c);
    if (!isMcpConnectorToken(token)) {
      return c.json({ error: "not_found", message: "connector not found" }, 404);
    }
    const connector = await store.currentMcpConnector(token);
    return c.json({ connector });
  });

  routes.delete("/:id", async (c) => {
    requireAuth0Jwt(c);
    await store.revokeMcpConnector(c.get("auth"), c.req.param("id"));
    return c.json({ ok: true });
  });

  return routes;
}
