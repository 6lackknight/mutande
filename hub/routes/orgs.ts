import { Hono } from "hono";
import { auth0Middleware, authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";
import type { CreateOrgInput, UpdateOrgInput } from "../store/types.ts";

export function createOrgRoutes(store: HubStore) {
  const orgRoutes = new Hono<HubEnv>();

  orgRoutes.post("/", auth0Middleware(store), async (c) => {
    const body = await c.req.json<CreateOrgInput>();
    const result = await store.createOrgForUser(c.get("auth0"), body);
    return c.json(result, 201);
  });

  orgRoutes.patch("/", authMiddleware(store), async (c) => {
    const body = await c.req.json<UpdateOrgInput>();
    const result = await store.updateOrgSlug(c.get("auth"), body);
    return c.json(result);
  });

  return orgRoutes;
}
