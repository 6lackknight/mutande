import {
  assertEquals,
  assertExists,
  assertStringIncludes,
} from "jsr:@std/assert@1";
import { createApp } from "../main.ts";
import { loadConfig } from "../config.ts";
import { createTestTokenVerifier } from "../auth/oauth.ts";
import { HubClient } from "../hub/client.ts";
import { SessionStore } from "../transport/sessions.ts";
import {
  acceptsEventStream,
  acceptsPostMcp,
} from "../transport/sse.ts";

function testConfig() {
  return loadConfig({
    get(key: string) {
      const map: Record<string, string> = {
        MCP_PUBLIC_URL: "https://mcp.test",
        AUTH0_DOMAIN: "auth.test",
        AUTH0_AUDIENCE: "https://hub.mutande.test",
        MUTANDE_HUB_URL: "http://hub.test",
        MCP_DEFAULT_AGENT_SLUG: "chatgpt",
      };
      return map[key];
    },
  });
}

function fakeHub(): HubClient {
  const hub = new HubClient("http://hub.test");
  hub.getMe = () =>
    Promise.resolve({
      auth0_sub: "auth0|u1",
      email: "u@acme.co",
      onboarded: true,
      user: { id: "uid", handle: "u@acme", org_id: "org" },
      org: { id: "org", slug: "acme" },
    });
  hub.connectMcpAgent = (_token, input) =>
    Promise.resolve({
      agent: {
        id: "agent-web-1",
        user_id: "uid",
        slug: input.slug,
        created_at: "2026-01-01T00:00:00.000Z",
        transport: "mcp",
      },
    });
  hub.listThreads = () => Promise.resolve({ threads: [] });
  return hub;
}

async function setup() {
  const config = testConfig();
  const { verifier, signToken } = await createTestTokenVerifier({
    issuer: "https://auth.test/",
    audience: "https://hub.mutande.test",
  });
  const sessions = new SessionStore();
  // Inject session store via createMcpRoutes — createApp doesn't expose it,
  // so build a thin app the same way for tests.
  const { createMcpRoutes } = await import("./mcp.ts");
  const { createHealthRoutes } = await import("./health.ts");
  const { createOauthRoutes } = await import("./oauth.ts");
  const { Hono } = await import("hono");
  const hub = fakeHub();
  const app = new Hono();
  app.route("/", createHealthRoutes(config));
  app.route("/", createOauthRoutes(config));
  app.route("/", createMcpRoutes(config, verifier, hub, { sessions }));
  const token = await signToken({ sub: "auth0|u1", email: "u@acme.co" });
  return { app, token, sessions, hub, signToken };
}

Deno.test("acceptsEventStream requires text/event-stream", () => {
  assertEquals(acceptsEventStream(undefined), false);
  assertEquals(acceptsEventStream("application/json"), false);
  assertEquals(acceptsEventStream("text/event-stream"), true);
  assertEquals(
    acceptsEventStream("application/json, text/event-stream"),
    true,
  );
  assertEquals(acceptsEventStream("*/*"), true);
});

Deno.test("acceptsPostMcp tolerates json-only Accept", () => {
  assertEquals(acceptsPostMcp(undefined), true);
  assertEquals(acceptsPostMcp("application/json"), true);
  assertEquals(
    acceptsPostMcp("application/json, text/event-stream"),
    true,
  );
  assertEquals(acceptsPostMcp("text/plain"), false);
});

Deno.test("GET /mcp without auth returns 401", async () => {
  const { app } = await setup();
  const res = await app.request("https://mcp.test/mcp", {
    method: "GET",
    headers: { Accept: "text/event-stream" },
  });
  assertEquals(res.status, 401);
  assertExists(res.headers.get("WWW-Authenticate"));
});

Deno.test("GET /mcp without Accept text/event-stream returns 406", async () => {
  const { app, token } = await setup();
  const res = await app.request("https://mcp.test/mcp", {
    method: "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
    },
  });
  assertEquals(res.status, 406);
});

Deno.test("GET /mcp opens SSE stream with session header", async () => {
  const { app, token } = await setup();
  const res = await app.request("https://mcp.test/mcp", {
    method: "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "text/event-stream",
    },
  });
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Content-Type"), "text/event-stream");
  assertExists(res.headers.get("Mcp-Session-Id"));
  assertEquals(res.headers.get("Cache-Control"), "no-cache, no-transform");

  // Read first chunk (connected comment) then cancel.
  const reader = res.body!.getReader();
  const { value } = await reader.read();
  assertExists(value);
  const text = new TextDecoder().decode(value);
  assertStringIncludes(text, ": connected");
  await reader.cancel();
});

Deno.test("GET /mcp with foreign session id returns 404", async () => {
  const { app, token, sessions, signToken } = await setup();
  const other = await signToken({ sub: "auth0|other" });
  // Create session owned by other user.
  const foreign = sessions.create("auth0|other", "chatgpt");

  const res = await app.request("https://mcp.test/mcp", {
    method: "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "text/event-stream",
      "Mcp-Session-Id": foreign.id,
    },
  });
  assertEquals(res.status, 404);
  // silence unused
  assertEquals(typeof other, "string");
});

Deno.test("POST initialize returns Mcp-Session-Id and tools still work", async () => {
  const { app, token } = await setup();
  const init = await app.request("https://mcp.test/mcp", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: { name: "test", version: "0" },
      },
    }),
  });
  assertEquals(init.status, 200);
  const sessionId = init.headers.get("Mcp-Session-Id");
  assertExists(sessionId);
  const initBody = await init.json();
  assertEquals(initBody.result.serverInfo.name, "mutande-mcp");

  const health = await app.request("https://mcp.test/mcp", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
      "Mcp-Session-Id": sessionId!,
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 2,
      method: "tools/call",
      params: { name: "health", arguments: {} },
    }),
  });
  assertEquals(health.status, 200);
  const healthBody = await health.json();
  const text = healthBody.result.content[0].text as string;
  assertStringIncludes(text, "agent-web-1");
  assertStringIncludes(text, "u@acme");
});

Deno.test("POST notification-only returns 202", async () => {
  const { app, token } = await setup();
  const res = await app.request("https://mcp.test/mcp", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      method: "notifications/initialized",
    }),
  });
  assertEquals(res.status, 202);
});

Deno.test("DELETE /mcp terminates session", async () => {
  const { app, token, sessions } = await setup();
  const created = sessions.create("auth0|u1", "chatgpt");
  const res = await app.request("https://mcp.test/mcp", {
    method: "DELETE",
    headers: {
      Authorization: `Bearer ${token}`,
      "Mcp-Session-Id": created.id,
    },
  });
  assertEquals(res.status, 200);
  assertEquals(sessions.get(created.id), undefined);
});

Deno.test("DELETE /mcp without session returns 400", async () => {
  const { app, token } = await setup();
  const res = await app.request("https://mcp.test/mcp", {
    method: "DELETE",
    headers: { Authorization: `Bearer ${token}` },
  });
  assertEquals(res.status, 400);
});

Deno.test("createApp still mounts POST /mcp", async () => {
  const config = testConfig();
  const { verifier, signToken } = await createTestTokenVerifier({
    issuer: "https://auth.test/",
    audience: "https://hub.mutande.test",
  });
  const { app } = createApp({
    config,
    verifier,
    hub: fakeHub(),
  });
  const token = await signToken({ sub: "auth0|u1", email: "u@acme.co" });
  const res = await app.request("https://mcp.test/mcp", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "tools/list",
      params: {},
    }),
  });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(Array.isArray(body.result.tools), true);
});

Deno.test(
  "ChatGPT discovery: initialize + tools/list with MCP-aud token",
  async () => {
    const mcpAud = "https://mcp.mutande.online";
    const config = loadConfig({
      get(key: string) {
        const map: Record<string, string> = {
          MCP_PUBLIC_URL: "https://mcp.mutande.online",
          AUTH0_DOMAIN: "auth.mutande.online",
          AUTH0_AUDIENCE: "https://hub.mutande.app",
          AUTH0_MCP_AUDIENCE: mcpAud,
          MUTANDE_HUB_URL: "http://hub.test",
          MCP_DEFAULT_AGENT_SLUG: "chatgpt",
        };
        return map[key];
      },
    });
    assertEquals(config.auth0McpAudience, mcpAud);

    const { verifier, signToken } = await createTestTokenVerifier({
      issuer: "https://auth.mutande.online/",
      audience: ["https://hub.mutande.app", mcpAud],
    });
    const { createMcpRoutes } = await import("./mcp.ts");
    const { Hono } = await import("hono");
    const hub = fakeHub();
    const app = new Hono();
    app.route("/", createMcpRoutes(config, verifier, hub));

    const token = await signToken(
      { sub: "auth0|chatgpt", email: "u@acme.co" },
      { audience: mcpAud, azp: "tpc_chatgpt" },
    );

    // ChatGPT often sends Accept: application/json only during discovery.
    const init = await app.request("https://mcp.mutande.online/mcp", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: {
          protocolVersion: "2025-03-26",
          capabilities: {},
          clientInfo: { name: "chatgpt", version: "0" },
        },
      }),
    });
    assertEquals(init.status, 200);
    const sessionId = init.headers.get("Mcp-Session-Id");
    assertExists(sessionId);
    const initBody = await init.json();
    assertEquals(initBody.result.serverInfo.name, "mutande-mcp");

    const list = await app.request("https://mcp.mutande.online/mcp", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        Accept: "application/json",
        "Mcp-Session-Id": sessionId!,
      },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 2,
        method: "tools/list",
        params: {},
      }),
    });
    assertEquals(list.status, 200);
    const listBody = await list.json();
    assertEquals(Array.isArray(listBody.result.tools), true);
    assertEquals(listBody.result.tools.length > 0, true);
  },
);

Deno.test("invalid audience returns 401 invalid_token", async () => {
  const config = testConfig();
  const { verifier } = await createTestTokenVerifier({
    issuer: "https://auth.test/",
    audience: "https://hub.mutande.test",
  });
  const wrong = await createTestTokenVerifier({
    issuer: "https://auth.test/",
    audience: "https://wrong.audience",
  });
  const { createMcpRoutes } = await import("./mcp.ts");
  const { Hono } = await import("hono");
  const app = new Hono();
  app.route("/", createMcpRoutes(config, verifier, fakeHub()));
  const token = await wrong.signToken({ sub: "auth0|u1" });

  const res = await app.request("https://mcp.test/mcp", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "tools/list",
      params: {},
    }),
  });
  assertEquals(res.status, 401);
  const www = res.headers.get("WWW-Authenticate") ?? "";
  assertStringIncludes(www, 'error="invalid_token"');
  const body = await res.json();
  assertEquals(body.error, "unauthorized");
});
