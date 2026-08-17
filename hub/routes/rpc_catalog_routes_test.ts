/**
 * Golden: every hub route the RPC catalog declares for passthrough methods
 * exists in the mounted app (proto/generated/rpc-routes.g.json is generated
 * from proto/rpc-catalog.json — see proto/codegen/).
 *
 * Bearer routes sit behind auth middleware, so an unauthenticated request
 * must yield 401 — a 404 means the catalog and the hub disagree. Public
 * routes must answer with hub JSON (Hono's bare "404 Not Found" text body
 * is the missing-route signal).
 */

import { assert, assertEquals } from "jsr:@std/assert@1";
import { createApp } from "../main.ts";
import table from "../../proto/generated/rpc-routes.g.json" with { type: "json" };

Deno.test("catalog passthrough routes exist on the hub", async () => {
  const kv = await Deno.openKv(":memory:");
  try {
    const { app } = await createApp(kv);
    for (const route of table.routes) {
      const path = route.path.replaceAll(/\{[a-z_]+\}/g, "test-id");
      const res = await app.request(path, { method: route.verb });
      if (route.auth === "public") {
        assert(
          res.headers.get("content-type")?.includes("application/json"),
          `${route.rpc}: ${route.verb} ${route.path} → ${res.status} without JSON body (route missing?)`,
        );
      } else {
        assertEquals(
          res.status,
          401,
          `${route.rpc}: ${route.verb} ${route.path} → ${res.status} (expected 401; 404 means the route is missing)`,
        );
      }
      await res.body?.cancel();
    }
  } finally {
    kv.close();
  }
});
