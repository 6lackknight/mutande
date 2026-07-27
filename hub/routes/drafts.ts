import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";
import type { Envelope } from "../store/types.ts";

export function createDraftRoutes(store: HubStore) {
  const draftRoutes = new Hono<HubEnv>();
  draftRoutes.use("*", authMiddleware(store));

  draftRoutes.get("/", async (c) => {
    const result = await store.listDrafts(c.get("auth"));
    return c.json(result);
  });

  draftRoutes.post("/", async (c) => {
    const { envelope } = await c.req.json<{ envelope: Envelope }>();
    const draft = await store.createDraft(c.get("auth"), envelope);
    return c.json({ draft }, 201);
  });

  draftRoutes.get("/:id", async (c) => {
    const draft = await store.getDraft(c.get("auth"), c.req.param("id"));
    return c.json({ draft });
  });

  draftRoutes.put("/:id", async (c) => {
    const { envelope } = await c.req.json<{ envelope: Envelope }>();
    const draft = await store.updateDraft(c.get("auth"), c.req.param("id"), envelope);
    return c.json({ draft });
  });

  draftRoutes.delete("/:id", async (c) => {
    await store.deleteDraft(c.get("auth"), c.req.param("id"));
    return c.body(null, 204);
  });

  return draftRoutes;
}
