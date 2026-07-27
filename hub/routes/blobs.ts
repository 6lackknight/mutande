import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";

export function createBlobRoutes(store: HubStore) {
  const blobRoutes = new Hono<HubEnv>();
  blobRoutes.use("*", authMiddleware(store));

  blobRoutes.post("/upload-url", async (c) => {
    const { size_bytes, content_type } = await c.req.json<{
      size_bytes: number;
      content_type?: string;
    }>();
    const result = await store.createUploadUrl(c.get("auth"), size_bytes, content_type);
    return c.json(result);
  });

  blobRoutes.post("/:id/download-url", async (c) => {
    const result = await store.createDownloadUrl(c.get("auth"), c.req.param("id"));
    return c.json(result);
  });

  return blobRoutes;
}
