import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";
import type {
  ConnectAgentInput,
  RegisterAgentInput,
  RenameAgentInput,
  SetDefaultAgentInput,
  SetRouterInput,
  SetTransportDefaultInput,
} from "../store/types.ts";

export function createAgentRoutes(store: HubStore) {
  const agentRoutes = new Hono<HubEnv>();
  agentRoutes.use("*", authMiddleware(store));

  agentRoutes.get("/", async (c) => {
    const handle = c.req.query("handle");
    if (handle) {
      const result = await store.listAgentsForHandle(c.get("auth"), handle);
      return c.json(result);
    }
    const result = await store.listAgents(c.get("auth"));
    return c.json(result);
  });

  agentRoutes.get("/router", async (c) => {
    const result = await store.getRouter(c.get("auth"));
    return c.json(result);
  });

  agentRoutes.put("/router", async (c) => {
    const body = await c.req.json<SetRouterInput>();
    const result = await store.setRouter(c.get("auth"), body);
    return c.json(result);
  });

  /** Preferred transport per display slug (Settings). */
  agentRoutes.get("/transport-defaults", async (c) => {
    const result = await store.getTransportPrefs(c.get("auth"));
    return c.json(result);
  });

  agentRoutes.put("/transport-defaults", async (c) => {
    const body = await c.req.json<SetTransportDefaultInput>();
    const result = await store.setTransportDefault(c.get("auth"), body);
    return c.json(result);
  });

  /**
   * Capability handshake — transport is hub-assigned from the path
   * (authenticated connection type), never from the client body.
   * L0 hosted MCP will hit /connect/mcp after OAuth; sidecar daemon uses /connect/sidecar.
   */
  agentRoutes.post("/connect/sidecar", async (c) => {
    const body = await c.req.json<ConnectAgentInput>();
    const agent = await store.connectAgent(c.get("auth"), "sidecar", body);
    return c.json({ agent }, 201);
  });

  agentRoutes.post("/connect/mcp", async (c) => {
    // L0: hosted MCP server calls this after Auth0 OAuth binding.
    const body = await c.req.json<ConnectAgentInput>();
    const agent = await store.connectAgent(c.get("auth"), "mcp", body);
    return c.json({ agent }, 201);
  });

  /**
   * Short-term compat alias for early L0 docs/clients.
   * Canonical path is POST /v1/agents/connect/mcp.
   */
  agentRoutes.post("/web", async (c) => {
    const body = await c.req.json<ConnectAgentInput>();
    const agent = await store.connectAgent(c.get("auth"), "mcp", body);
    return c.json({ agent }, 201);
  });

  agentRoutes.post("/", async (c) => {
    const body = await c.req.json<RegisterAgentInput>();
    const agent = await store.addAgent(c.get("auth"), body);
    return c.json({ agent }, 201);
  });

  /** Legacy register = sidecar connect (compat for daemon). */
  agentRoutes.post("/register", async (c) => {
    const body = await c.req.json<RegisterAgentInput>();
    const agent = await store.registerAgent(c.get("auth"), body);
    return c.json({ agent }, 201);
  });

  agentRoutes.put("/default", async (c) => {
    const body = await c.req.json<SetDefaultAgentInput>();
    const agent = await store.setDefaultAgent(c.get("auth"), body);
    return c.json({ agent });
  });

  agentRoutes.patch("/:agentId", async (c) => {
    const body = await c.req.json<RenameAgentInput>();
    const agent = await store.renameAgent(c.get("auth"), c.req.param("agentId"), body);
    return c.json({ agent });
  });

  return agentRoutes;
}
