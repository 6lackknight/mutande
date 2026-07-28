import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";
import type {
  RegisterAgentInput,
  RenameAgentInput,
  SetDefaultAgentInput,
  SetRouterInput,
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

  agentRoutes.post("/", async (c) => {
    const body = await c.req.json<RegisterAgentInput>();
    const agent = await store.addAgent(c.get("auth"), body);
    return c.json({ agent }, 201);
  });

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
