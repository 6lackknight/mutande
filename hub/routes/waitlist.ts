import { Hono } from "hono";
import { HubError } from "../store/errors.ts";
import type { HubStore } from "../store/store.ts";

export function createWaitlistRoutes(store: HubStore) {
  const routes = new Hono();

  /** Public marketing waitlist — no Auth0. */
  routes.post("/", async (c) => {
    let body: {
      email?: unknown;
      ai_hosts?: unknown;
      /** @deprecated prefer ai_hosts */
      ai_host?: unknown;
      oses?: unknown;
      /** @deprecated prefer oses */
      os?: unknown;
      share_frequency?: unknown;
      share_methods?: unknown;
      website?: unknown;
    } = {};
    try {
      body = await c.req.json();
    } catch {
      throw new HubError("JSON body required", "invalid_argument", 400);
    }
    // Honeypot: bots fill hidden "website" — accept silently.
    if (typeof body.website === "string" && body.website.trim()) {
      return c.json({ ok: true }, 201);
    }
    const entry = await store.submitWaitlist({
      email: typeof body.email === "string" ? body.email : "",
      ai_hosts: parseStringList(body.ai_hosts, body.ai_host),
      oses: parseStringList(body.oses, body.os),
      share_frequency: typeof body.share_frequency === "string"
        ? body.share_frequency
        : "",
      share_methods: parseStringList(body.share_methods),
    });
    return c.json({ waitlist: entry }, 201);
  });

  return routes;
}

function parseStringList(primary: unknown, legacy?: unknown): string[] {
  if (Array.isArray(primary)) {
    return primary.filter((v): v is string => typeof v === "string");
  }
  if (typeof primary === "string" && primary.trim()) {
    return [primary];
  }
  if (typeof legacy === "string" && legacy.trim()) {
    return [legacy];
  }
  return [];
}
