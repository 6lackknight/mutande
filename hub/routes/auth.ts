import { Hono } from "hono";
import { auth0Middleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";

/** Auth0 identity routes. Web calls GET /v1/auth/me. */
export function createAuthRoutes(store: HubStore) {
  const authRoutes = new Hono<HubEnv>();
  authRoutes.get("/me", auth0Middleware(store), async (c) => {
    return c.json(await store.getMe(c.get("auth0")));
  });
  return authRoutes;
}
