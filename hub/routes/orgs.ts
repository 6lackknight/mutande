import { Hono } from "hono";
import { auth0Middleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";
import type { CreateOrgInput } from "../store/types.ts";

export function createOrgRoutes(store: HubStore) {
  const orgRoutes = new Hono<HubEnv>();
  orgRoutes.use("*", auth0Middleware(store));
  orgRoutes.post("/", async (c) => {
    const body = await c.req.json<CreateOrgInput>();
    const result = await store.createOrgForUser(c.get("auth0"), body);
    return c.json(result, 201);
  });
  return orgRoutes;
}
