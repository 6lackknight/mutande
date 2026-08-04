import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import { HubError } from "../store/errors.ts";
import type { HubStore } from "../store/store.ts";
import type { Feedback } from "../store/types.ts";

export function createFeedbackRoutes(store: HubStore) {
  const routes = new Hono<HubEnv>();
  routes.use("*", authMiddleware(store));

  routes.post("/", async (c) => {
    let body: {
      message?: unknown;
      category?: unknown;
      app_version?: unknown;
      platform?: unknown;
    } = {};
    try {
      body = await c.req.json();
    } catch {
      throw new HubError("JSON body required", "invalid_argument", 400);
    }
    if (typeof body.message !== "string") {
      throw new HubError("message must be a string", "invalid_argument", 400);
    }
    const platform = parsePlatform(body.platform);
    const feedback = await store.submitFeedback(c.get("auth"), {
      message: body.message,
      category: typeof body.category === "string" ? body.category : undefined,
      app_version: typeof body.app_version === "string"
        ? body.app_version
        : undefined,
      platform,
    });
    return c.json({ feedback }, 201);
  });

  return routes;
}

function parsePlatform(value: unknown): Feedback["platform"] | undefined {
  if (value === "macos" || value === "ios" || value === "web") return value;
  return undefined;
}
