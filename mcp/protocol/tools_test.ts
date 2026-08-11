import { assertEquals } from "jsr:@std/assert@1";
import { toolDefinitions, IMPLEMENTED_TOOLS } from "./tools.ts";
import { handleMcpRequest } from "./handler.ts";
import type { McpSession } from "../session/bind.ts";
import { HubClient } from "../hub/client.ts";
import {
  filterThreadsForWebAgent,
  threadForWebAgent,
} from "../hub/inbox.ts";
import type { ThreadMeta } from "../hub/types.ts";

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

function meta(partial: Partial<ThreadMeta> & Pick<ThreadMeta, "id">): ThreadMeta {
  return {
    kind: "direct",
    status: "open",
    from: "bob@acme/claude",
    from_user_id: "bob",
    audience: "u@acme/chatgpt",
    org_id: "org",
    participant_count: 2,
    reply_count: 0,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-01T00:00:00.000Z",
    encryption_mode: "app_envelope",
    audience_agent_id: "agent-web-1",
    ...partial,
  };
}

Deno.test("tool list marks inbox tools implemented", () => {
  const names = toolDefinitions().map((t) => t.name);
  assertEquals(names.includes("list_threads"), true);
  assertEquals(IMPLEMENTED_TOOLS.has("list_threads"), true);
  assertEquals(IMPLEMENTED_TOOLS.has("get_thread"), true);
  assertEquals(IMPLEMENTED_TOOLS.has("reply_to_thread"), true);
});

Deno.test("health tool returns bound session", async () => {
  const hub = new HubClient("http://hub.test");
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: { name: "health", arguments: {} },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  assertEquals(res?.result && typeof res.result === "object", true);
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError ?? false, false);
  const body = JSON.parse(result.content[0].text);
  assertEquals(body.ok, true);
  assertEquals(body.agent_id, "agent-web-1");
  assertEquals(body.slug, "chatgpt");
});

Deno.test("threadForWebAgent filters by agent_id and mode", () => {
  assertEquals(
    threadForWebAgent(meta({ id: "t1" }), "agent-web-1"),
    true,
  );
  assertEquals(
    threadForWebAgent(
      meta({ id: "t2", audience_agent_id: "other", encryption_mode: "app_envelope" }),
      "agent-web-1",
    ),
    false,
  );
  assertEquals(
    threadForWebAgent(
      meta({ id: "t3", encryption_mode: "e2e", audience_agent_id: "agent-web-1" }),
      "agent-web-1",
    ),
    false,
  );
  assertEquals(
    threadForWebAgent(
      meta({
        id: "t4",
        kind: "broadcast",
        audience: "@all",
        audience_agent_id: undefined,
        encryption_mode: "app_envelope",
      }),
      "agent-web-1",
    ),
    true,
  );
});

Deno.test("filterThreadsForWebAgent drops e2e and other agents", () => {
  const threads = [
    meta({ id: "mine" }),
    meta({ id: "e2e", encryption_mode: "e2e" }),
    meta({ id: "other", audience_agent_id: "x" }),
  ];
  const filtered = filterThreadsForWebAgent(threads, "agent-web-1");
  assertEquals(filtered.map((t) => t.id), ["mine"]);
});

Deno.test("list_threads caught_up when hub returns empty", async () => {
  const hub = new HubClient("http://hub.test");
  const orig = hub.listThreads.bind(hub);
  hub.listThreads = () => Promise.resolve({ threads: [] });
  try {
    const res = await handleMcpRequest(
      {
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: { name: "list_threads", arguments: {} },
      },
      { session: fakeSession, serverVersion: "0.1.0", hub },
    );
    const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
    assertEquals(result.isError ?? false, false);
    const body = JSON.parse(result.content[0].text);
    assertEquals(body.caught_up, true);
    assertEquals(body.threads.length, 0);
  } finally {
    hub.listThreads = orig;
  }
});

Deno.test("list_threads returns matching app_envelope threads", async () => {
  const hub = new HubClient("http://hub.test");
  hub.listThreads = () =>
    Promise.resolve({
      threads: [
        meta({ id: "mine", your_status: "pending" }),
        meta({ id: "other", audience_agent_id: "nope" }),
      ],
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 3,
      method: "tools/call",
      params: { name: "list_threads", arguments: { filter: "needs_action" } },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  const body = JSON.parse(result.content[0].text);
  assertEquals(body.caught_up, false);
  assertEquals(body.threads.map((t: ThreadMeta) => t.id), ["mine"]);
});

Deno.test("initialize returns serverInfo", async () => {
  const hub = new HubClient("http://hub.test");
  const res = await handleMcpRequest(
    { jsonrpc: "2.0", id: 0, method: "initialize", params: {} },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { serverInfo: { name: string } };
  assertEquals(result.serverInfo.name, "mutande-mcp");
});
