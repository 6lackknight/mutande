import { assertEquals } from "jsr:@std/assert@1";
import { Hono } from "hono";
import { handleHubError } from "../middleware/auth.ts";
import { createAdminRoutes } from "./admin.ts";
import { createAuthRoutes } from "./auth.ts";
import { createDeviceRoutes } from "./devices.ts";
import { createMeRoutes } from "./me.ts";
import { createOnboardingRoutes } from "./onboarding.ts";
import { createOrgRoutes } from "./orgs.ts";
import { createStoreWithTestAuth } from "../store/store.ts";

async function testApp() {
  const kv = await Deno.openKv(":memory:");
  const { store, signToken } = await createStoreWithTestAuth(kv);
  const app = new Hono();
  app.onError((err) => handleHubError(err));
  app.route("/v1/auth", createAuthRoutes(store));
  app.route("/v1/orgs", createOrgRoutes(store));
  app.route("/v1/onboarding", createOnboardingRoutes(store));
  app.route("/v1/me", createMeRoutes(store));
  app.route("/v1/devices", createDeviceRoutes(store));
  app.route("/v1/admin", createAdminRoutes(store));
  return { app, store, signToken, kv };
}

function bearer(token: string) {
  return { Authorization: `Bearer ${token}` };
}

Deno.test("GET /v1/auth/me onboarding state", async () => {
  const { app, signToken, kv } = await testApp();
  try {
    const token = await signToken({ sub: "auth0|new", email: "new@example.com" });
    const res = await app.request("/v1/auth/me", { headers: bearer(token) });
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body.onboarded, false);
    assertEquals(body.needs_onboarding, true);
  } finally {
    kv.close();
  }
});

Deno.test("GET /v1/auth/me 401 missing auth", async () => {
  const { app, kv } = await testApp();
  try {
    assertEquals((await app.request("/v1/auth/me")).status, 401);
  } finally {
    kv.close();
  }
});

Deno.test("POST /v1/orgs", async () => {
  const { app, signToken, kv } = await testApp();
  try {
    const token = await signToken({ sub: "auth0|founder", email: "founder@co.io" });
    const res = await app.request("/v1/orgs", {
      method: "POST",
      headers: { ...bearer(token), "Content-Type": "application/json" },
      body: JSON.stringify({ slug: "co", name: "Co LLC" }),
    });
    assertEquals(res.status, 201);
    assertEquals((await res.json()).user.role, "org_admin");
  } finally { kv.close(); }
});

Deno.test("POST /v1/onboarding/join", async () => {
  const { app, store, signToken, kv } = await testApp();
  try {
    const adminToken = await signToken({ sub: "auth0|admin", email: "admin@team.io" });
    await app.request("/v1/orgs", {
      method: "POST",
      headers: { ...bearer(adminToken), "Content-Type": "application/json" },
      body: JSON.stringify({ slug: "team", name: "Team" }),
    });
    const admin = await store.getUserByAuth0Sub("auth0|admin");
    const invite = await store.createInvite(store.authContextFromUser(admin!));
    const memberToken = await signToken({ sub: "auth0|member", email: "member@team.io" });
    const res = await app.request("/v1/onboarding/join", {
      method: "POST",
      headers: { ...bearer(memberToken), "Content-Type": "application/json" },
      body: JSON.stringify({ invite_code: invite.code }),
    });
    assertEquals(res.status, 201);
    assertEquals((await res.json()).user.handle, "member@team");
  } finally { kv.close(); }
});

Deno.test("POST /v1/devices requires onboarding", async () => {
  const { app, signToken, kv } = await testApp();
  try {
    const token = await signToken({ sub: "auth0|x", email: "x@test.com" });
    const res = await app.request("/v1/devices", {
      method: "POST",
      headers: { ...bearer(token), "Content-Type": "application/json" },
      body: JSON.stringify({ pubkey: "pk", platform: "macos" }),
    });
    assertEquals(res.status, 403);
  } finally { kv.close(); }
});

Deno.test("admin invites org_admin only", async () => {
  const { app, store, signToken, kv } = await testApp();
  try {
    const adminToken = await signToken({ sub: "auth0|adm", email: "adm@org.test" });
    await app.request("/v1/orgs", {
      method: "POST",
      headers: { ...bearer(adminToken), "Content-Type": "application/json" },
      body: JSON.stringify({ slug: "org", name: "Org" }),
    });
    assertEquals((await app.request("/v1/admin/invites", { method: "POST", headers: bearer(adminToken) })).status, 201);
    const admin = await store.getUserByAuth0Sub("auth0|adm");
    const code = (await store.listInvites(store.authContextFromUser(admin!))).invites[0]!.code;
    const memberToken = await signToken({ sub: "auth0|mem", email: "mem@org.test" });
    await app.request("/v1/onboarding/join", {
      method: "POST",
      headers: { ...bearer(memberToken), "Content-Type": "application/json" },
      body: JSON.stringify({ invite_code: code }),
    });
    assertEquals((await app.request("/v1/admin/invites", { method: "POST", headers: bearer(memberToken) })).status, 403);
  } finally { kv.close(); }
});
