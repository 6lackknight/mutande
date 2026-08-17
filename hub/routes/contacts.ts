import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";

export function createContactRoutes(store: HubStore) {
  const contactRoutes = new Hono<HubEnv>();
  contactRoutes.use("*", authMiddleware(store));

  /** Same-org contacts + broadcast. Daemon `list_contacts` is core-owned. */
  contactRoutes.get("/", async (c) => {
    const result = await store.listContacts(c.get("auth"));
    return c.json(result);
  });

  return contactRoutes;
}
