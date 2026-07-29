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
    let email: string | undefined;
    try {
      const body = await c.req.json() as { email?: unknown };
      if (typeof body.email === "string" && body.email.trim()) {
        email = body.email.trim();
      }
    } catch {
      // empty body is fine
    }
    const invite = await store.createInviteAsAdmin(c.get("auth"), { email });
    return c.json({ invite }, 201);
  });
  return adminRoutes;
}
