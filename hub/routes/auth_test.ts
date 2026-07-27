import { assertEquals } from "jsr:@std/assert@1";
import { Hono } from "hono";
import { handleHubError } from "../middleware/auth.ts";
import { HubStore } from "../store/store.ts";
import { createAuthRoutes } from "./auth.ts";

const JWT_SECRET = "test-secret";

function testApp(store: HubStore) {
  const app = new Hono();
  app.onError((err) => handleHubError(err));
  app.route("/v1/auth", createAuthRoutes(store));
  return app;
}

Deno.test("/me returns 401 on bad JWT", async () => {
  const kv = await Deno.openKv(":memory:");
  const store = new HubStore(kv, JWT_SECRET);
  const app = testApp(store);

  try {
    const res = await app.request("/v1/auth/me", {
      headers: { Authorization: "Bearer not.a.valid.jwt" },
    });
    assertEquals(res.status, 401);
    const body = await res.json();
    assertEquals(body.error, "unauthorized");
  } finally {
    kv.close();
  }
});

Deno.test("/me returns 401 when Authorization missing", async () => {
  const kv = await Deno.openKv(":memory:");
  const store = new HubStore(kv, JWT_SECRET);
  const app = testApp(store);

  try {
    const res = await app.request("/v1/auth/me");
    assertEquals(res.status, 401);
  } finally {
    kv.close();
  }
});
