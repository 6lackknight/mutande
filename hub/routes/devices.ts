import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";
import type { RegisterDeviceInput } from "../store/types.ts";

export function createDeviceRoutes(store: HubStore) {
  const deviceRoutes = new Hono<HubEnv>();
  deviceRoutes.use("*", authMiddleware(store));
  deviceRoutes.post("/", async (c) => {
    const body = await c.req.json<RegisterDeviceInput>();
    const device = await store.registerDevice(c.get("auth"), body);
    return c.json({ device }, 201);
  });
  return deviceRoutes;
}
