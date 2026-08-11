import { Hono } from "hono";
import type { McpConfig } from "../config.ts";

export function createHealthRoutes(config: McpConfig) {
  const routes = new Hono();
  routes.get("/health", (c) =>
    c.json({
      ok: true,
      service: "mutande-mcp",
      public_url: config.publicUrl,
      hub_url: config.hubUrl,
    })
  );
  return routes;
}
