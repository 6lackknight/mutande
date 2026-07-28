import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";

export function createAdminRoutes(store: HubStore) {
  const adminRoutes = new Hono<HubEnv>();
  adminRoutes.use("*", authMiddleware(store));
  adminRoutes.get("/invites", async (c) => {
    return c.json(await store.listInvitesAsAdmin(c.get("auth")));
  });
  adminRoutes.post("/invites", async (c) => {
    const invite = await store.createInviteAsAdmin(c.get("auth"));
    return c.json({ invite }, 201);
  });
  return adminRoutes;
}
