import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";
import type { AppEnvelopePayload, Envelope, ThreadFilter } from "../store/types.ts";

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
      envelope?: Envelope;
      app_envelope?: AppEnvelopePayload;
      from_agent?: string;
      from_agent_id?: string;
      turns?: { user_id: string; actor: "agent" | "human" }[];
      collab_id?: string;
      lane_id?: string;
      assigned_to?: string;
      watchers?: string[];
      tags?: string[];
      due_on?: string;
      checklist?: { id?: string; text: string; done?: boolean }[];
    }>();
    const result = await store.createThread(c.get("auth"), body);
    return c.json(result, 201);
  });

  threadRoutes.get("/:id", async (c) => {
    const result = await store.getThread(c.get("auth"), c.req.param("id"));
    return c.json(result);
  });

  /**
   * Web/MCP pull — app_envelope content only (§4.2.1).
   * Query `agent_id` optional; must belong to caller when set.
   */
  threadRoutes.get("/:id/app-messages", async (c) => {
    const agentId = c.req.query("agent_id") ?? undefined;
    const result = await store.fetchAppMessages(c.get("auth"), c.req.param("id"), {
      agent_id: agentId,
    });
    return c.json(result);
  });

  threadRoutes.post("/:id/messages", async (c) => {
    const body = await c.req.json<{
      envelope?: Envelope;
      app_envelope?: AppEnvelopePayload;
      from_agent?: string;
      from_agent_id?: string;
      to_agent?: string;
      parent_message_id?: string;
      turns?: { user_id: string; actor: "agent" | "human" }[];
    }>();
    const result = await store.postReply(c.get("auth"), c.req.param("id"), body);
    return c.json(result, 201);
  });

  threadRoutes.post("/:id/replies", async (c) => {
    const body = await c.req.json<{
      envelope?: Envelope;
      app_envelope?: AppEnvelopePayload;
      from_agent?: string;
      from_agent_id?: string;
      to_agent?: string;
      parent_message_id?: string;
      turns?: { user_id: string; actor: "agent" | "human" }[];
    }>();
    const result = await store.postReply(c.get("auth"), c.req.param("id"), body);
    return c.json(result, 201);
  });

  threadRoutes.post("/:id/messages/:messageId/upvote", async (c) => {
    const body = await c.req.json<{ from_agent?: string; from_agent_id?: string }>()
      .catch(() => ({}));
    const result = await store.toggleMessageUpvote(
      c.get("auth"),
      c.req.param("id"),
      c.req.param("messageId"),
      body,
    );
    return c.json(result);
  });

  threadRoutes.post("/:id/messages/:messageId/receipt", async (c) => {
    const body = await c.req.json<{ from_agent?: string; from_agent_id?: string }>()
      .catch(() => ({}));
    const result = await store.postMessageReceipt(
      c.get("auth"),
      c.req.param("id"),
      c.req.param("messageId"),
      body,
    );
    return c.json(result);
  });

  threadRoutes.post("/:id/downgrade-proposals/:proposalId/approve", async (c) => {
    const result = await store.approveThreadDowngrade(
      c.get("auth"),
      c.req.param("id"),
      c.req.param("proposalId"),
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
