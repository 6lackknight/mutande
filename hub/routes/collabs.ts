import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";
import type { Envelope } from "../store/types.ts";

export function createCollabRoutes(store: HubStore) {
  const routes = new Hono<HubEnv>();
  routes.use("*", authMiddleware(store));

  routes.post("/", async (c) => {
    const body = await c.req.json<{
      name: string;
      steerer_handles?: string[];
      roster_addresses?: string[];
      instructions?: string;
      instructions_sealed?: { envelope_id: string; updated_by: string };
      artifacts?: Array<{
        kind: "file" | "link";
        label?: string;
        title?: string;
        url?: string;
        name?: string;
        mime?: string;
        size?: number;
        content?: string;
        envelope?: Envelope;
      }>;
    }>();
    const collab = await store.createCollab(c.get("auth"), body);
    return c.json({ collab }, 201);
  });

  routes.get("/:id", async (c) => {
    const collab = await store.getCollab(c.get("auth"), c.req.param("id"));
    return c.json({ collab });
  });

  routes.post("/:id/lane", async (c) => {
    const body = await c.req.json<{
      thread_id: string;
      lane_id: string;
      before_thread_id?: string;
      after_thread_id?: string;
    }>();
    const result = await store.setLane(c.get("auth"), c.req.param("id"), body);
    return c.json(result);
  });

  routes.post("/:id/learnings", async (c) => {
    const body = await c.req.json<{
      notes: string;
      from_agent?: string;
      from_agent_id?: string;
      envelope?: Envelope;
    }>();
    const result = await store.addLearning(c.get("auth"), c.req.param("id"), body);
    return c.json(result, 201);
  });

  routes.post("/:id/instructions", async (c) => {
    const body = await c.req.json<{
      instructions?: string;
      instructions_sealed?: { envelope_id: string; updated_by: string };
    }>();
    const collab = await store.updateCollabInstructions(
      c.get("auth"),
      c.req.param("id"),
      body,
    );
    return c.json({ collab });
  });

  routes.post("/:id/artifacts", async (c) => {
    const body = await c.req.json<{
      artifacts: Array<{
        kind: "file" | "link";
        label?: string;
        title?: string;
        url?: string;
        name?: string;
        mime?: string;
        size?: number;
        content?: string;
        envelope?: Envelope;
      }>;
    }>();
    const collab = await store.addCollabArtifacts(
      c.get("auth"),
      c.req.param("id"),
      body,
    );
    return c.json({ collab });
  });

  routes.post("/:id/lists/:laneId/rename", async (c) => {
    const body = await c.req.json<{ name: string }>();
    const collab = await store.renameCollabList(
      c.get("auth"),
      c.req.param("id"),
      { lane_id: c.req.param("laneId"), name: body.name },
    );
    return c.json({ collab });
  });

  routes.post("/:id/downgrade", async (c) => {
    const body = await c.req.json<{
      cause_address: string;
      approvers: string[];
    }>();
    const collab = await store.applyCollabDowngrade(
      c.get("auth"),
      c.req.param("id"),
      body,
    );
    return c.json({ collab });
  });

  return routes;
}
