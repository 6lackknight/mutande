import { assertEquals } from "jsr:@std/assert@1";
import { Hono } from "hono";
import { handleHubError } from "../middleware/auth.ts";
import { createAdminRoutes } from "./admin.ts";
import { createOrgRoutes } from "./orgs.ts";
import { createWaitlistRoutes } from "./waitlist.ts";
import { createStoreWithTestAuth } from "../store/store.ts";

async function testApp() {
  const kv = await Deno.openKv(":memory:");
  const { store, signToken } = await createStoreWithTestAuth(kv);
  const app = new Hono();
  app.onError((err) => handleHubError(err));
  app.route("/v1/orgs", createOrgRoutes(store));
  app.route("/v1/waitlist", createWaitlistRoutes(store));
  app.route("/v1/admin", createAdminRoutes(store));
  return { app, signToken, kv };
}

function bearer(token: string) {
  return { Authorization: `Bearer ${token}` };
}

const sample = {
  email: "friend@example.com",
  ai_hosts: ["Cursor", "Claude Desktop"],
  oses: ["macOS"],
  share_frequency: "A few times a week",
  share_methods: ["Copy / paste", "Email"],
};

Deno.test("POST /v1/waitlist + GET /v1/admin/waitlist", async () => {
  const { app, signToken, kv } = await testApp();
  try {
    const post = await app.request("/v1/waitlist", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(sample),
    });
    assertEquals(post.status, 201);
    const created = await post.json();
    assertEquals(created.waitlist.email, "friend@example.com");
    assertEquals(created.waitlist.ai_hosts, ["Cursor", "Claude Desktop"]);

    const token = await signToken({ sub: "auth0|admin", email: "admin@co.io" });
    await app.request("/v1/orgs", {
      method: "POST",
      headers: { ...bearer(token), "Content-Type": "application/json" },
      body: JSON.stringify({ slug: "co", name: "Co" }),
    });

    const orgAdminOnly = await app.request("/v1/admin/waitlist", {
      headers: bearer(token),
    });
    assertEquals(orgAdminOnly.status, 403);

    const opsToken = await signToken({
      sub: "auth0|admin",
      email: "admin@co.io",
      roles: ["SuperAdmin"],
    });
    const list = await app.request("/v1/admin/waitlist", {
      headers: bearer(opsToken),
    });
    assertEquals(list.status, 200);
    const body = await list.json();
    assertEquals(body.waitlist.length, 1);
    assertEquals(body.waitlist[0].share_frequency, "A few times a week");
    assertEquals(body.waitlist[0].share_methods, ["Copy / paste", "Email"]);
  } finally {
    kv.close();
  }
});

Deno.test("POST /v1/waitlist rejects bad email", async () => {
  const { app, kv } = await testApp();
  try {
    const res = await app.request("/v1/waitlist", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...sample, email: "not-an-email" }),
    });
    assertEquals(res.status, 400);
  } finally {
    kv.close();
  }
});

Deno.test("POST /v1/waitlist honeypot returns 201 without storing", async () => {
  const { app, signToken, kv } = await testApp();
  try {
    const post = await app.request("/v1/waitlist", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...sample, website: "http://spam.example" }),
    });
    assertEquals(post.status, 201);

    const token = await signToken({
      sub: "auth0|admin2",
      email: "a2@co.io",
      roles: ["SuperAdmin"],
    });
    await app.request("/v1/orgs", {
      method: "POST",
      headers: { ...bearer(token), "Content-Type": "application/json" },
      body: JSON.stringify({ slug: "co2" }),
    });
    const list = await app.request("/v1/admin/waitlist", {
      headers: bearer(token),
    });
    const body = await list.json();
    assertEquals(body.waitlist.length, 0);
  } finally {
    kv.close();
  }
});
