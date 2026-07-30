import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";
import type { Envelope, ThreadFilter } from "../store/types.ts";

export function createThreadRoutes(store: HubStore) {
  const threadRoutes = new Hono<HubEnv>();
  threadRoutes.use("*", authMiddleware(store));

  threadRoutes.get("/", async (c) => {
    const filter = c.req.query("filter") as ThreadFilter | undefined;
    const result = await store.listThreads(c.get("auth"), filter);
    return c.json(result);
  });

  threadRoutes.post("/", async (c) => {
    const body = await c.req.json<{
      to: string;
      envelope: Envelope;
      from_agent?: string;
    }>();
    const result = await store.createThread(c.get("auth"), body);
    return c.json(result, 201);
  });

  threadRoutes.get("/:id", async (c) => {
    const result = await store.getThread(c.get("auth"), c.req.param("id"));
    return c.json(result);
  });

  threadRoutes.post("/:id/messages", async (c) => {
    const body = await c.req.json<{
      envelope: Envelope;
      from_agent?: string;
      to_agent?: string;
      parent_message_id?: string;
    }>();
    const result = await store.postReply(c.get("auth"), c.req.param("id"), body);
    return c.json(result, 201);
  });

  threadRoutes.post("/:id/replies", async (c) => {
    const body = await c.req.json<{
      envelope: Envelope;
      from_agent?: string;
      to_agent?: string;
      parent_message_id?: string;
    }>();
    const result = await store.postReply(c.get("auth"), c.req.param("id"), body);
    return c.json(result, 201);
  });

  threadRoutes.post("/:id/messages/:messageId/upvote", async (c) => {
    const body = await c.req.json<{ from_agent?: string }>().catch(() => ({}));
    const result = await store.toggleMessageUpvote(
      c.get("auth"),
      c.req.param("id"),
      c.req.param("messageId"),
      body,
    );
    return c.json(result);
  });

  threadRoutes.post("/:id/close", async (c) => {
    const result = await store.closeThread(c.get("auth"), c.req.param("id"));
    return c.json(result);
  });

  threadRoutes.delete("/:id", async (c) => {
    const result = await store.deleteThread(c.get("auth"), c.req.param("id"));
    return c.json(result);
  });

  return threadRoutes;
}
