import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";
import type { RegisterInput } from "../store/types.ts";

export function createAuthRoutes(store: HubStore) {
  const authRoutes = new Hono<HubEnv>();

  authRoutes.post("/register", async (c) => {
    const body = await c.req.json<RegisterInput>();
    const result = await store.register(body);
    return c.json(result, 201);
  });

  authRoutes.post("/token", async (c) => {
    const { refresh_token } = await c.req.json<{ refresh_token: string }>();
    const result = await store.refreshToken(refresh_token);
    return c.json(result);
  });

  authRoutes.get("/me", authMiddleware(store), async (c) => {
    const auth = c.get("auth");
    const user = await store.getMe(auth.userId);
    return c.json({ user });
  });

  return authRoutes;
}
