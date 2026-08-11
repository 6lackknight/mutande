import { assertEquals } from "jsr:@std/assert@1";
import { toolDefinitions, IMPLEMENTED_TOOLS } from "./tools.ts";
import { handleMcpRequest } from "./handler.ts";
import type { McpSession } from "../session/bind.ts";
import { HubClient, HubClientError } from "../hub/client.ts";
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
  for (const t of [
    "list_agents",
    "list_contacts",
    "forward_draft",
    "close_thread",
    "delete_thread",
    "upvote_message",
    "mark_processed",
  ]) {
    assertEquals(names.includes(t), true);
    assertEquals(IMPLEMENTED_TOOLS.has(t), true);
  }
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
  const result = res!.result as {
    serverInfo: {
      name: string;
      title?: string;
      description?: string;
      websiteUrl?: string;
      icons?: Array<{ src: string }>;
    };
    instructions?: string;
  };
  assertEquals(result.serverInfo.name, "mutande-mcp");
  assertEquals(result.serverInfo.title, "mutande");
  assertEquals(typeof result.serverInfo.description, "string");
  assertEquals(result.serverInfo.websiteUrl, "https://mutande.online/docs/hosted-mcp");
  assertEquals(result.serverInfo.icons?.[0]?.src.includes("icon-192.png"), true);
  assertEquals(typeof result.instructions, "string");
});

function parseToolText(res: Awaited<ReturnType<typeof handleMcpRequest>>) {
  const result = res!.result as {
    content: Array<{ text: string }>;
    isError?: boolean;
  };
  return {
    isError: result.isError ?? false,
    body: JSON.parse(result.content[0].text) as Record<string, unknown>,
    text: result.content[0].text,
  };
}

Deno.test("list_agents returns dual transport slots", async () => {
  const hub = new HubClient("http://hub.test");
  hub.listAgents = () =>
    Promise.resolve({
      agents: [
        {
          id: "a1",
          user_id: "uid",
          slug: "chatgpt",
          created_at: "2026-01-01T00:00:00.000Z",
          transport: "mcp",
        },
        {
          id: "a2",
          user_id: "uid",
          slug: "chatgpt",
          created_at: "2026-01-01T00:00:00.000Z",
          transport: "sidecar",
        },
      ],
      default_agent_id: "a2",
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 10,
      method: "tools/call",
      params: { name: "list_agents", arguments: {} },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const { isError, body } = parseToolText(res);
  assertEquals(isError, false);
  assertEquals((body.agents as unknown[]).length, 2);
  assertEquals(
    (body.agents as Array<{ transport: string }>).map((a) => a.transport).sort(),
    ["mcp", "sidecar"],
  );
});

Deno.test("list_contacts merges org and external", async () => {
  const hub = new HubClient("http://hub.test");
  hub.listContacts = () =>
    Promise.resolve({
      contacts: [
        { handle: "@all@acme", pubkey: null, devices: [], kind: "broadcast" },
        { handle: "bob@acme", pubkey: "pk", devices: [], kind: "org" },
      ],
    });
  hub.listExternalContacts = () =>
    Promise.resolve({
      contacts: [
        {
          handle: "eve@other",
          pubkey: null,
          devices: [],
          kind: "external",
          external_link_id: "link1",
        },
      ],
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 11,
      method: "tools/call",
      params: { name: "list_contacts", arguments: {} },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const { isError, body } = parseToolText(res);
  assertEquals(isError, false);
  assertEquals((body.contacts as unknown[]).length, 2);
  assertEquals((body.external_contacts as Array<{ handle: string }>)[0].handle, "eve@other");
});

Deno.test("forward_draft creates app_envelope thread", async () => {
  const hub = new HubClient("http://hub.test");
  hub.createThread = (_token, input) => {
    assertEquals(input.to, "@all");
    assertEquals(input.from_agent, "chatgpt");
    assertEquals(input.from_agent_id, "agent-web-1");
    assertEquals(input.app_envelope.notes, "hello team");
    return Promise.resolve({
      thread: meta({
        id: "new-t",
        audience: "@all",
        kind: "broadcast",
        from_agent_id: "agent-web-1",
      }),
      message_id: "m1",
    });
  };
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 12,
      method: "tools/call",
      params: {
        name: "forward_draft",
        arguments: {
          recipient: "@all",
          bundle: { notes: "hello team", subject: "Hi" },
        },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const { isError, body } = parseToolText(res);
  assertEquals(isError, false);
  assertEquals(body.ok, true);
  assertEquals(body.thread_id, "new-t");
  assertEquals(body.message_id, "m1");
});

Deno.test("forward_draft @cursor returns thread_id with from_agent_id", async () => {
  const hub = new HubClient("http://hub.test");
  hub.createThread = (_token, input) => {
    assertEquals(input.to, "@cursor");
    assertEquals(input.from_agent_id, "agent-web-1");
    assertEquals(input.from_agent, "chatgpt");
    return Promise.resolve({
      thread: meta({
        id: "cursor-t",
        audience: "u@acme/cursor",
        audience_agent_id: "agent-cursor-1",
        from_agent_id: "agent-web-1",
        encryption_mode: "app_envelope",
      }),
      message_id: "m-cursor",
    });
  };
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 21,
      method: "tools/call",
      params: {
        name: "forward_draft",
        arguments: {
          recipient: "@cursor",
          bundle: {
            subject: "orgs prd",
            notes: "please review",
            resources: [{
              name: "mutande-organisations-prd.md",
              content: "# Organisations\n\nDraft",
            }],
          },
        },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const { isError, body } = parseToolText(res);
  assertEquals(isError, false);
  assertEquals(body.ok, true);
  assertEquals(body.thread_id, "cursor-t");
  assertEquals(body.message_id, "m-cursor");
  assertEquals(body.encryption_mode, "app_envelope");
});

Deno.test("forward_draft rejects /mnt/data path without content", async () => {
  const hub = new HubClient("http://hub.test");
  let called = false;
  hub.createThread = () => {
    called = true;
    return Promise.reject(new Error("should not create"));
  };
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 22,
      method: "tools/call",
      params: {
        name: "forward_draft",
        arguments: {
          recipient: "@cursor",
          bundle: {
            notes: "attached prd",
            resources: [{
              name: "mutande-organisations-prd.md",
              path: "/mnt/data/mutande-organisations-prd.md",
            }],
          },
        },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as {
    content: Array<{ text: string }>;
    isError?: boolean;
  };
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("/mnt/data"), true);
  assertEquals(result.content[0].text.toLowerCase().includes("content"), true);
  assertEquals(called, false);
});

Deno.test("forward_draft refuses hub empty success without thread_id", async () => {
  const hub = new HubClient("http://hub.test");
  hub.createThread = () =>
    Promise.resolve({
      thread: meta({ id: "" }),
      message_id: "",
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 23,
      method: "tools/call",
      params: {
        name: "forward_draft",
        arguments: {
          recipient: "@cursor",
          bundle: { notes: "hi" },
        },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as {
    content: Array<{ text: string }>;
    isError?: boolean;
  };
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("thread_id"), true);
});

Deno.test("list_threads open includes threads this web agent created", async () => {
  const hub = new HubClient("http://hub.test");
  hub.listThreads = () =>
    Promise.resolve({
      threads: [
        meta({
          id: "sent",
          from_agent_id: "agent-web-1",
          audience_agent_id: "agent-cursor-1",
          audience: "u@acme/cursor",
          your_status: "replied",
        }),
        meta({
          id: "other",
          from_agent_id: "someone-else",
          audience_agent_id: "nope",
        }),
      ],
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 24,
      method: "tools/call",
      params: { name: "list_threads", arguments: { filter: "open" } },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const { isError, body } = parseToolText(res);
  assertEquals(isError, false);
  assertEquals(body.caught_up, false);
  assertEquals((body.threads as ThreadMeta[]).map((t) => t.id), ["sent"]);
});

Deno.test("forward_draft refuses hub E2E wire error", async () => {
  const hub = new HubClient("http://hub.test");
  hub.createThread = () =>
    Promise.reject(
      new HubClientError(
        "E2E threads require envelope (not app_envelope)",
        400,
      ),
    );
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 13,
      method: "tools/call",
      params: {
        name: "forward_draft",
        arguments: {
          recipient: "bob@acme/claude",
          bundle: { notes: "secret" },
        },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("sidecar"), true);
  assertEquals(result.content[0].text.includes("app_envelope"), true);
});

Deno.test("forward_draft refuses empty bundle", async () => {
  const hub = new HubClient("http://hub.test");
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 14,
      method: "tools/call",
      params: {
        name: "forward_draft",
        arguments: { recipient: "@all", bundle: {} },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("bundle must include"), true);
});

Deno.test("close_thread success", async () => {
  const hub = new HubClient("http://hub.test");
  hub.closeThread = () =>
    Promise.resolve({
      thread: meta({ id: "t-close", status: "closed" }),
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 15,
      method: "tools/call",
      params: { name: "close_thread", arguments: { thread_id: "t-close" } },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const { isError, body } = parseToolText(res);
  assertEquals(isError, false);
  assertEquals(body.ok, true);
  assertEquals((body.thread as { status: string }).status, "closed");
});

Deno.test("delete_thread success", async () => {
  const hub = new HubClient("http://hub.test");
  hub.deleteThread = () => Promise.resolve({ ok: true as const });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 16,
      method: "tools/call",
      params: { name: "delete_thread", arguments: { thread_id: "t-del" } },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const { isError, body } = parseToolText(res);
  assertEquals(isError, false);
  assertEquals(body.ok, true);
  assertEquals(body.thread_id, "t-del");
});

Deno.test("upvote_message success", async () => {
  const hub = new HubClient("http://hub.test");
  hub.upvoteMessage = (_t, threadId, messageId, opts) => {
    assertEquals(threadId, "t1");
    assertEquals(messageId, "m1");
    assertEquals(opts?.from_agent, "chatgpt");
    assertEquals(opts?.from_agent_id, "agent-web-1");
    return Promise.resolve({
      upvoted: true,
      upvotes: { count: 1, upvotes: [], your_upvotes: ["agent-web-1"] },
    });
  };
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 17,
      method: "tools/call",
      params: {
        name: "upvote_message",
        arguments: { thread_id: "t1", message_id: "m1" },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const { isError, body } = parseToolText(res);
  assertEquals(isError, false);
  assertEquals(body.upvoted, true);
});

Deno.test("mark_processed returns N/A payload", async () => {
  const hub = new HubClient("http://hub.test");
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 18,
      method: "tools/call",
      params: { name: "mark_processed", arguments: { thread_id: "t1" } },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const { isError, body } = parseToolText(res);
  assertEquals(isError, false);
  assertEquals(body.na, true);
  assertEquals(body.ok, true);
});

Deno.test("close_thread requires thread_id", async () => {
  const hub = new HubClient("http://hub.test");
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 19,
      method: "tools/call",
      params: { name: "close_thread", arguments: {} },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError, true);
});

Deno.test("unknown desktop-only tool refused", async () => {
  const hub = new HubClient("http://hub.test");
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 20,
      method: "tools/call",
      params: { name: "get_safety_number", arguments: {} },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("unknown tool"), true);
});
