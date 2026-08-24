import { assertEquals } from "jsr:@std/assert@1";
import { Hono } from "hono";
import { handleHubError } from "../middleware/auth.ts";
import { createAgentRoutes } from "./agents.ts";
import { createMeRoutes } from "./me.ts";
import { createMcpConnectorRoutes } from "./mcp_connectors.ts";
import { createOrgRoutes } from "./orgs.ts";
import { createStoreWithTestAuth } from "../store/store.ts";
import { MCP_CONNECTOR_PREFIX } from "../store/mcp_connectors.ts";

async function testApp() {
  const kv = await Deno.openKv(":memory:");
  const { store, signToken } = await createStoreWithTestAuth(kv);
  const app = new Hono();
  app.onError((err) => handleHubError(err));
  app.route("/v1/orgs", createOrgRoutes(store));
  app.route("/v1/me", createMeRoutes(store));
  app.route("/v1/agents", createAgentRoutes(store));
  app.route("/v1/mcp/connectors", createMcpConnectorRoutes(store));
  return { app, store, signToken, kv };
}

function bearer(token: string) {
  return { Authorization: `Bearer ${token}` };
}

Deno.test("POST /v1/mcp/connectors mints key; connector token works on /v1/me", async () => {
  const { app, signToken, kv } = await testApp();
  try {
    const jwt = await signToken({ sub: "auth0|u1", email: "u@acme.test" });
    const org = await app.request("/v1/orgs", {
      method: "POST",
      headers: { ...bearer(jwt), "Content-Type": "application/json" },
      body: JSON.stringify({ slug: "acme", name: "Acme" }),
    });
    assertEquals(org.status, 201);

    const mint = await app.request("/v1/mcp/connectors", {
      method: "POST",
      headers: { ...bearer(jwt), "Content-Type": "application/json" },
      body: JSON.stringify({ label: "Grok Bot" }),
    });
    assertEquals(mint.status, 201);
    const minted = await mint.json();
    assertEquals(typeof minted.token, "string");
    assertEquals(minted.token.startsWith(MCP_CONNECTOR_PREFIX), true);
    assertEquals(minted.connector.slug, "grok");

    const me = await app.request("/v1/me", { headers: bearer(minted.token) });
    assertEquals(me.status, 200);
    const meBody = await me.json();
    assertEquals(meBody.onboarded, true);
    assertEquals(meBody.auth0_sub, "auth0|u1");

    const current = await app.request("/v1/mcp/connectors/current", {
      headers: bearer(minted.token),
    });
    assertEquals(current.status, 200);
    const curBody = await current.json();
    assertEquals(curBody.connector.id, minted.connector.id);
    assertEquals(curBody.connector.slug, "grok");

    const connect = await app.request("/v1/agents/connect/mcp", {
      method: "POST",
      headers: { ...bearer(minted.token), "Content-Type": "application/json" },
      body: JSON.stringify({ slug: "grok" }),
    });
    assertEquals(connect.status, 201);
    const agent = (await connect.json()).agent;
    assertEquals(agent.slug, "grok");
    assertEquals(agent.transport, "mcp");

    const listed = await app.request("/v1/mcp/connectors", { headers: bearer(jwt) });
    assertEquals(listed.status, 200);
    const listBody = await listed.json();
    assertEquals(listBody.connectors.length, 1);
    assertEquals("token" in listBody.connectors[0], false);
  } finally {
    kv.close();
  }
});

Deno.test("connector token cannot mint more keys", async () => {
  const { app, signToken, kv } = await testApp();
  try {
    const jwt = await signToken({ sub: "auth0|u2", email: "u2@acme.test" });
    await app.request("/v1/orgs", {
      method: "POST",
      headers: { ...bearer(jwt), "Content-Type": "application/json" },
      body: JSON.stringify({ slug: "acme2", name: "Acme2" }),
    });
    const mint = await app.request("/v1/mcp/connectors", {
      method: "POST",
      headers: { ...bearer(jwt), "Content-Type": "application/json" },
      body: "{}",
    });
    const token = (await mint.json()).token as string;

    const again = await app.request("/v1/mcp/connectors", {
      method: "POST",
      headers: { ...bearer(token), "Content-Type": "application/json" },
      body: "{}",
    });
    assertEquals(again.status, 403);
  } finally {
    kv.close();
  }
});

Deno.test("DELETE /v1/mcp/connectors/:id revokes", async () => {
  const { app, signToken, kv } = await testApp();
  try {
    const jwt = await signToken({ sub: "auth0|u3", email: "u3@acme.test" });
    await app.request("/v1/orgs", {
      method: "POST",
      headers: { ...bearer(jwt), "Content-Type": "application/json" },
      body: JSON.stringify({ slug: "acme3", name: "Acme3" }),
    });
    const mint = await app.request("/v1/mcp/connectors", {
      method: "POST",
      headers: { ...bearer(jwt), "Content-Type": "application/json" },
      body: JSON.stringify({ label: "tmp" }),
    });
    const minted = await mint.json();
    const del = await app.request(
      `/v1/mcp/connectors/${minted.connector.id}`,
      { method: "DELETE", headers: bearer(jwt) },
    );
    assertEquals(del.status, 200);
    const me = await app.request("/v1/me", { headers: bearer(minted.token) });
    assertEquals(me.status, 401);
  } finally {
    kv.close();
  }
});

Deno.test("GET /v1/mcp/connectors/current with JWT is 404", async () => {
  const { app, signToken, kv } = await testApp();
  try {
    const jwt = await signToken({ sub: "auth0|u4", email: "u4@acme.test" });
    await app.request("/v1/orgs", {
      method: "POST",
      headers: { ...bearer(jwt), "Content-Type": "application/json" },
      body: JSON.stringify({ slug: "acme4", name: "Acme4" }),
    });
    const res = await app.request("/v1/mcp/connectors/current", {
      headers: bearer(jwt),
    });
    assertEquals(res.status, 404);
  } finally {
    kv.close();
  }
});
