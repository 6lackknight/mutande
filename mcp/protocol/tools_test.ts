import { assertEquals } from "jsr:@std/assert@1";
import { toolDefinitions, IMPLEMENTED_TOOLS } from "./tools.ts";
import { handleMcpRequest } from "./handler.ts";
import type { McpSession } from "../session/bind.ts";

const fakeSession: McpSession = {
  accessToken: "test",
  claims: { sub: "auth0|u1", email: "u@acme.co" },
  me: {
    auth0_sub: "auth0|u1",
    onboarded: true,
    user: { id: "uid", handle: "u@acme" },
  },
  agent: {
    id: "agent-web-1",
    user_id: "uid",
    slug: "chatgpt",
    created_at: "2026-01-01T00:00:00.000Z",
    transport: "mcp",
  },
  slug: "chatgpt",
  boundAt: "2026-01-01T00:00:00.000Z",
};

Deno.test("tool list includes health and inbox stubs", () => {
  const names = toolDefinitions().map((t) => t.name);
  assertEquals(names.includes("health"), true);
  assertEquals(names.includes("list_threads"), true);
  assertEquals(IMPLEMENTED_TOOLS.has("health"), true);
});

Deno.test("health tool returns bound session", async () => {
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: { name: "health", arguments: {} },
    },
    { session: fakeSession, serverVersion: "0.1.0" },
  );
  assertEquals(res?.result && typeof res.result === "object", true);
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError ?? false, false);
  const body = JSON.parse(result.content[0].text);
  assertEquals(body.ok, true);
  assertEquals(body.agent_id, "agent-web-1");
  assertEquals(body.slug, "chatgpt");
});

Deno.test("list_threads stub returns not implemented", async () => {
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 2,
      method: "tools/call",
      params: { name: "list_threads", arguments: {} },
    },
    { session: fakeSession, serverVersion: "0.1.0" },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError: boolean };
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("not implemented"), true);
});

Deno.test("initialize returns serverInfo", async () => {
  const res = await handleMcpRequest(
    { jsonrpc: "2.0", id: 0, method: "initialize", params: {} },
    { session: fakeSession, serverVersion: "0.1.0" },
  );
  const result = res!.result as { serverInfo: { name: string } };
  assertEquals(result.serverInfo.name, "mutande-mcp");
});
