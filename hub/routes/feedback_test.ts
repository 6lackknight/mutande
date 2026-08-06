import { assertEquals } from "jsr:@std/assert@1";
import { Hono } from "hono";
import { handleHubError } from "../middleware/auth.ts";
import { createAdminRoutes } from "./admin.ts";
import { createFeedbackRoutes } from "./feedback.ts";
import { createOrgRoutes } from "./orgs.ts";
import { createStoreWithTestAuth } from "../store/store.ts";

async function testApp() {
  const kv = await Deno.openKv(":memory:");
  const { store, signToken } = await createStoreWithTestAuth(kv);
  const app = new Hono();
  app.onError((err) => handleHubError(err));
  app.route("/v1/orgs", createOrgRoutes(store));
  app.route("/v1/feedback", createFeedbackRoutes(store));
  app.route("/v1/admin", createAdminRoutes(store));
  return { app, signToken, kv };
}

function bearer(token: string) {
  return { Authorization: `Bearer ${token}` };
}

Deno.test("POST /v1/feedback + GET /v1/admin/feedback", async () => {
  const { app, signToken, kv } = await testApp();
  try {
    const token = await signToken({ sub: "auth0|pilot", email: "pilot@co.io" });
    await app.request("/v1/orgs", {
      method: "POST",
      headers: { ...bearer(token), "Content-Type": "application/json" },
      body: JSON.stringify({ slug: "co", name: "Co" }),
    });

    const post = await app.request("/v1/feedback", {
      method: "POST",
      headers: { ...bearer(token), "Content-Type": "application/json" },
      body: JSON.stringify({
        message: "Connect hosts was confusing",
        category: "onboarding",
        app_version: "0.1.0",
        platform: "macos",
      }),
    });
    assertEquals(post.status, 201);
    const created = await post.json();
    assertEquals(created.feedback.message, "Connect hosts was confusing");
    assertEquals(created.feedback.handle.endsWith("@co"), true);

    const orgAdminOnly = await app.request("/v1/admin/feedback", {
      headers: bearer(token),
    });
    assertEquals(orgAdminOnly.status, 403);

    const opsToken = await signToken({
      sub: "auth0|pilot",
      email: "pilot@co.io",
      roles: ["SuperAdmin"],
    });
    const list = await app.request("/v1/admin/feedback", {
      headers: bearer(opsToken),
    });
    assertEquals(list.status, 200);
    const body = await list.json();
    assertEquals(body.feedback.length, 1);
    assertEquals(body.feedback[0].message, "Connect hosts was confusing");
  } finally {
    kv.close();
  }
});

Deno.test("POST /v1/feedback rejects empty message", async () => {
  const { app, signToken, kv } = await testApp();
  try {
    const token = await signToken({ sub: "auth0|x", email: "x@co.io" });
    await app.request("/v1/orgs", {
      method: "POST",
      headers: { ...bearer(token), "Content-Type": "application/json" },
      body: JSON.stringify({ slug: "xco" }),
    });
    const res = await app.request("/v1/feedback", {
      method: "POST",
      headers: { ...bearer(token), "Content-Type": "application/json" },
      body: JSON.stringify({ message: "   " }),
    });
    assertEquals(res.status, 400);
  } finally {
    kv.close();
  }
});
