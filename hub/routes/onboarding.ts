import { Hono } from "hono";
import { auth0Middleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";
import type { JoinOrgInput } from "../store/types.ts";

export function createOnboardingRoutes(store: HubStore) {
  const onboardingRoutes = new Hono<HubEnv>();
  onboardingRoutes.use("*", auth0Middleware(store));
  onboardingRoutes.post("/join", async (c) => {
    const body = await c.req.json<JoinOrgInput>();
    const result = await store.joinOrgWithInvite(c.get("auth0"), body);
    return c.json(result, 201);
  });
  return onboardingRoutes;
}
