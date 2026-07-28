import { Hono } from "hono";
import { auth0Middleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";

/** Compat alias for GET /v1/me → same as /v1/auth/me */
export function createMeRoutes(store: HubStore) {
  const routes = new Hono<HubEnv>();
  routes.get("/", auth0Middleware(store), async (c) => {
    return c.json(await store.getMe(c.get("auth0")));
  });
  return routes;
}
