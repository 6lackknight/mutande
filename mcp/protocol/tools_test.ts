import { assertEquals } from "jsr:@std/assert@1";
import { toolDefinitions, IMPLEMENTED_TOOLS } from "./tools.ts";
import { handleMcpRequest, normalizeForwardDraftBundle } from "./handler.ts";
import type { McpSession } from "../session/bind.ts";
import { HubClient, HubClientError } from "../hub/client.ts";
import {
  filterThreadsForWebAgent,
  threadForWebAgent,
} from "../hub/inbox.ts";
import type { ThreadMeta, CollabView } from "../hub/types.ts";

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
    "list_collabs",
    "get_collab",
    "create_card",
    "set_lane",
    "add_learning",
    "forward_draft",
    "close_thread",
    "delete_thread",
    "upvote_message",
    "mark_processed",
    "publish_handshake",
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
      meta({ id: "t2b", audience_agent_id: "sidecar", encryption_mode: "app_envelope" }),
      "agent-web-1",
      "chatgpt",
    ),
    true,
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
        meta({
          id: "mine",
          your_status: "pending",
          last_subject: "Review please",
          from: "u@acme/cursor",
          audience: "u@acme/chatgpt",
        }),
        meta({ id: "other", audience_agent_id: "nope", audience: "u@acme/claude" }),
      ],
    });
  // Avoid soft-fail peek HTTP when last_* already present (and for the filtered-out row).
  hub.fetchAppMessages = () => Promise.reject(new Error("not used"));
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
  const row = body.threads[0] as ThreadMeta & {
    thread_id: string;
    title: string;
    subject?: string;
    participants: string[];
    to: string;
  };
  assertEquals(row.thread_id, "mine");
  assertEquals(row.subject, "Review please");
  assertEquals(row.title, "Review please");
  assertEquals(row.to, "u@acme/chatgpt");
  assertEquals(row.participants, ["cursor", "chatgpt"]);
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
  assertEquals(result.instructions!.includes("/mnt/data"), true);
  assertEquals(result.instructions!.includes("content_base64"), true);
  assertEquals(result.instructions!.includes("filter=open"), true);
  assertEquals(result.instructions!.includes("IS the named file"), true);
  assertEquals(result.instructions!.includes("attachments"), true);
  assertEquals(result.instructions!.includes("publish_handshake"), true);
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
  assertEquals(body.resource_count, 0);
  assertEquals(body.resource_names, []);
  assertEquals(body.attachments, []);
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
  assertEquals(body.resource_count, 1);
  assertEquals(body.resource_names, ["mutande-organisations-prd.md"]);
  assertEquals(body.attachments, [{
    name: "mutande-organisations-prd.md",
    bytes: new TextEncoder().encode("# Organisations\n\nDraft").length,
  }]);
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
          from: "u@acme/chatgpt",
          from_agent_id: "agent-web-1",
          audience_agent_id: "agent-cursor-1",
          audience: "u@acme/cursor",
          your_status: "replied",
        }),
        meta({
          id: "other",
          from_agent_id: "someone-else",
          audience_agent_id: "nope",
          audience: "u@acme/claude",
        }),
      ],
    });
  hub.fetchAppMessages = () =>
    Promise.resolve({
      thread: meta({ id: "sent", from_agent_id: "agent-web-1" }),
      messages: [
        {
          id: "m1",
          thread_id: "sent",
          from_user_id: "uid",
          from_handle: "u@acme/chatgpt",
          created_at: "2026-01-01T00:00:00.000Z",
          app_envelope: {
            version: 1,
            subject: "Handoff",
            notes: "please take this",
          },
        },
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
  const sent = (body.threads as Array<ThreadMeta & {
    participants: string[];
    title: string;
    subject?: string;
    preview?: string;
  }>)[0];
  assertEquals(sent.participants, ["chatgpt", "cursor"]);
  assertEquals(sent.subject, "Handoff");
  assertEquals(sent.title, "Handoff");
  assertEquals(sent.preview, "please take this");
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
  assertEquals(result.content[0].text.includes("inline content"), true);
});

Deno.test("normalizeForwardDraftBundle unwraps nested and prefers top-level", () => {
  assertEquals(
    normalizeForwardDraftBundle({
      recipient: "@cursor",
      bundle: {
        subject: "nested-subj",
        notes: "nested-notes",
        resources: [{ name: "a.md", content: "# A" }],
      },
    }),
    {
      subject: "nested-subj",
      notes: "nested-notes",
      resources: [{ name: "a.md", content: "# A" }],
    },
  );
  assertEquals(
    normalizeForwardDraftBundle({
      recipient: "@cursor",
      subject: "flat-subj",
      notes: "flat-notes",
      resources: [{ name: "b.md", content: "# B" }],
    }),
    {
      subject: "flat-subj",
      notes: "flat-notes",
      resources: [{ name: "b.md", content: "# B" }],
    },
  );
  // Top-level wins when both present; missing top-level fields keep nested.
  assertEquals(
    normalizeForwardDraftBundle({
      recipient: "@cursor",
      notes: "prefer-me",
      resources: [{ name: "top.md", content: "# Top" }],
      bundle: {
        subject: "keep-nested-subject",
        notes: "ignore-nested-notes",
        resources: [{ name: "nested.md", content: "# Nested" }],
      },
    }),
    {
      subject: "keep-nested-subject",
      notes: "prefer-me",
      resources: [{ name: "top.md", content: "# Top" }],
    },
  );
});

Deno.test("forward_draft flat top-level resources land in app_envelope", async () => {
  const hub = new HubClient("http://hub.test");
  hub.createThread = (_token, input) => {
    assertEquals(input.to, "@cursor");
    assertEquals(input.app_envelope.subject, "Review: flat");
    assertEquals(input.app_envelope.notes, "please review");
    const resources = input.app_envelope.resources as Array<
      Record<string, unknown>
    >;
    assertEquals(resources.length, 1);
    assertEquals(resources[0].name, "prd.md");
    assertEquals(resources[0].content, "# PRD\n\nFlat args");
    return Promise.resolve({
      thread: meta({
        id: "flat-t",
        audience: "u@acme/cursor",
        from_agent_id: "agent-web-1",
        encryption_mode: "app_envelope",
      }),
      message_id: "m-flat",
    });
  };
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 25,
      method: "tools/call",
      params: {
        name: "forward_draft",
        arguments: {
          recipient: "@cursor",
          subject: "Review: flat",
          notes: "please review",
          resources: [{ name: "prd.md", content: "# PRD\n\nFlat args" }],
        },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const { isError, body } = parseToolText(res);
  assertEquals(isError, false);
  assertEquals(body.ok, true);
  assertEquals(body.thread_id, "flat-t");
  assertEquals(body.message_id, "m-flat");
  assertEquals(body.resource_count, 1);
  assertEquals(body.resource_names, ["prd.md"]);
  assertEquals((body.attachments as Array<{ name: string }>)[0].name, "prd.md");
});

Deno.test("forward_draft nested bundle with content stores resource", async () => {
  const hub = new HubClient("http://hub.test");
  hub.createThread = (_token, input) => {
    assertEquals(input.app_envelope.subject, "Review: Mutande Organizations PRD v0.1");
    const resources = input.app_envelope.resources as Array<
      Record<string, unknown>
    >;
    assertEquals(resources.length, 1);
    assertEquals(resources[0].name, "mutande-organisations-prd.md");
    assertEquals(
      String(resources[0].content).startsWith("# PRD"),
      true,
    );
    return Promise.resolve({
      thread: meta({
        id: "nested-t",
        audience: "u@acme/cursor",
        from_agent_id: "agent-web-1",
        encryption_mode: "app_envelope",
      }),
      message_id: "m-nested",
    });
  };
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 26,
      method: "tools/call",
      params: {
        name: "forward_draft",
        arguments: {
          recipient: "@cursor",
          bundle: {
            subject: "Review: Mutande Organizations PRD v0.1",
            notes: "please review the PRD",
            resources: [{
              name: "mutande-organisations-prd.md",
              content: "# PRD ...",
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
  assertEquals(body.thread_id, "nested-t");
  assertEquals(body.resource_count, 1);
  assertEquals(body.resource_names, ["mutande-organisations-prd.md"]);
  assertEquals(
    (body.attachments as Array<{ name: string }>)[0].name,
    "mutande-organisations-prd.md",
  );
});

Deno.test("forward_draft mixed flat resources + nested notes prefers top-level resources", async () => {
  const hub = new HubClient("http://hub.test");
  hub.createThread = (_token, input) => {
    assertEquals(input.app_envelope.notes, "from bundle");
    assertEquals(input.app_envelope.subject, "from bundle");
    const resources = input.app_envelope.resources as Array<
      Record<string, unknown>
    >;
    assertEquals(resources[0].name, "top.md");
    assertEquals(resources[0].content, "# Top wins");
    return Promise.resolve({
      thread: meta({
        id: "mix-t",
        audience: "u@acme/cursor",
        from_agent_id: "agent-web-1",
      }),
      message_id: "m-mix",
    });
  };
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 27,
      method: "tools/call",
      params: {
        name: "forward_draft",
        arguments: {
          recipient: "@cursor",
          resources: [{ name: "top.md", content: "# Top wins" }],
          bundle: {
            subject: "from bundle",
            notes: "from bundle",
            resources: [{ name: "nested.md", content: "# Nested loses" }],
          },
        },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const { isError, body } = parseToolText(res);
  assertEquals(isError, false);
  assertEquals(body.resource_count, 1);
  assertEquals(body.resource_names, ["top.md"]);
  assertEquals((body.attachments as Array<{ name: string }>)[0].name, "top.md");
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

Deno.test("publish_handshake upserts profile and replies", async () => {
  const hub = new HubClient("http://hub.test");
  hub.putAgentHandshake = (_token, agentId, card) => {
    assertEquals(agentId, "agent-web-1");
    assertEquals(card.host, "ChatGPT");
    return Promise.resolve({
      agent: fakeSession.agent,
      handshake: {
        host: "ChatGPT",
        address: "u@acme/chatgpt",
        models: ["gpt-5"],
        published_at: "2026-08-19T12:00:00.000Z",
      },
    });
  };
  hub.replyToThread = (_t, threadId, input) => {
    assertEquals(threadId, "t-hs");
    assertEquals(input.app_envelope.subject, "Handshake");
    assertEquals(
      (input.app_envelope as { handshake?: { host?: string } }).handshake?.host,
      "ChatGPT",
    );
    return Promise.resolve({ message_id: "m-hs" });
  };
  hub.fetchAppMessages = () =>
    Promise.resolve({
      thread: meta({ id: "t-hs", audience_agent_id: "agent-web-1" }),
      messages: [],
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 40,
      method: "tools/call",
      params: {
        name: "publish_handshake",
        arguments: { thread_id: "t-hs", host: "ChatGPT", models: ["gpt-5"] },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const { isError, body } = parseToolText(res);
  assertEquals(isError, false);
  assertEquals(body.ok, true);
  assertEquals(body.thread_id, "t-hs");
  assertEquals(body.message_id, "m-hs");
  assertEquals((body.handshake as { host: string }).host, "ChatGPT");
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

Deno.test("list_collabs returns hub boards", async () => {
  const hub = new HubClient("http://hub.test");
  hub.listCollabs = () =>
    Promise.resolve({
      collabs: [{
        id: "c1",
        name: "sprint",
        encryption_mode: "app_envelope",
        card_count: 0,
      } as CollabView],
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 21,
      method: "tools/call",
      params: { name: "list_collabs", arguments: {} },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  const body = JSON.parse(result.content[0].text);
  assertEquals(body.collabs[0].id, "c1");
  assertEquals(body.collabs[0].name, "sprint");
  assertEquals(body.collabs[0].status, "open");
  assertEquals(Array.isArray(body.collabs[0].people), true);
  assertEquals(Array.isArray(body.collabs[0].agents), true);
});

Deno.test("get_collab returns board object with cards and artifacts", async () => {
  const hub = new HubClient("http://hub.test");
  hub.getCollab = () =>
    Promise.resolve({
      collab: {
        id: "c-berry",
        name: "BerrySure",
        encryption_mode: "app_envelope",
        instructions: "Ship the alpha.",
        steerers: [{ user_id: "u1", handle: "Alice@Acme" }],
        roster: [{ address: "Alice@Acme/ChatGPT", transport: "mcp" }],
        lists: [{ id: "backlog", name: "Backlog", position: 0 }],
        cards: [{
          id: "t-card",
          last_subject: "Landing copy",
          lane_id: "backlog",
          status: "open",
        }],
        artifacts: [{ kind: "link", label: "Staging", url: "https://staging.example.com" }],
      } as unknown as CollabView,
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 23,
      method: "tools/call",
      params: { name: "get_collab", arguments: { collab_id: "c-berry" } },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  const body = JSON.parse(result.content[0].text);
  assertEquals(body.collab.name, "BerrySure");
  assertEquals(body.collab.people[0].handle, "alice@acme");
  assertEquals(body.collab.agents[0].address, "alice@acme/chatgpt");
  assertEquals(body.collab.cards[0].thread_id, "t-card");
  assertEquals(body.collab.artifacts[0].kind, "link");
});

Deno.test("get_collab is forbidden for non-participants", async () => {
  const hub = new HubClient("http://hub.test");
  hub.getCollab = () =>
    Promise.reject(new HubClientError("Not a collab member", 403));
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 24,
      method: "tools/call",
      params: { name: "get_collab", arguments: { collab_id: "c-secret" } },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("403"), true);
});

Deno.test("list_collabs is empty for non-participants", async () => {
  const hub = new HubClient("http://hub.test");
  hub.listCollabs = () => Promise.resolve({ collabs: [] });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 25,
      method: "tools/call",
      params: { name: "list_collabs", arguments: {} },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  const body = JSON.parse(result.content[0].text);
  assertEquals(body.collabs.length, 0);
});

Deno.test("list_collabs omits archived boards", async () => {
  const hub = new HubClient("http://hub.test");
  hub.listCollabs = () =>
    Promise.resolve({
      collabs: [
        { id: "c1", name: "sprint", encryption_mode: "app_envelope" } as CollabView,
        {
          id: "c-old",
          name: "done",
          encryption_mode: "app_envelope",
          status: "archived",
        } as CollabView,
      ],
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 31,
      method: "tools/call",
      params: { name: "list_collabs", arguments: {} },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  const body = JSON.parse(result.content[0].text);
  assertEquals(body.collabs.map((c: { id: string }) => c.id), ["c1"]);
});

Deno.test("create_card refuses archived collab", async () => {
  const hub = new HubClient("http://hub.test");
  hub.getCollab = () =>
    Promise.resolve({
      collab: {
        id: "c-old",
        name: "done",
        encryption_mode: "app_envelope",
        status: "archived",
      } as CollabView,
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 32,
      method: "tools/call",
      params: {
        name: "create_card",
        arguments: { collab_id: "c-old", title: "Nope" },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("this collab is archived"), true);
});

Deno.test("set_lane refuses archived collab", async () => {
  const hub = new HubClient("http://hub.test");
  hub.getCollab = () =>
    Promise.resolve({
      collab: {
        id: "c-old",
        name: "done",
        encryption_mode: "app_envelope",
        status: "archived",
      } as CollabView,
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 33,
      method: "tools/call",
      params: {
        name: "set_lane",
        arguments: { collab_id: "c-old", thread_id: "t1", lane_id: "doing" },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("this collab is archived"), true);
});

Deno.test("add_learning refuses archived collab", async () => {
  const hub = new HubClient("http://hub.test");
  hub.getCollab = () =>
    Promise.resolve({
      collab: {
        id: "c-old",
        name: "done",
        encryption_mode: "app_envelope",
        status: "archived",
      } as CollabView,
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 34,
      method: "tools/call",
      params: {
        name: "add_learning",
        arguments: { collab_id: "c-old", notes: "Nope" },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("this collab is archived"), true);
});

Deno.test("add_learning refuses e2e collab", async () => {
  const hub = new HubClient("http://hub.test");
  hub.getCollab = () =>
    Promise.resolve({
      collab: {
        id: "c-e2e",
        name: "sealed",
        encryption_mode: "e2e",
      },
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 22,
      method: "tools/call",
      params: {
        name: "add_learning",
        arguments: { collab_id: "c-e2e", notes: "secret" },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("E2E"), true);
});

Deno.test("create_card files a thread on collab + lane name", async () => {
  const hub = new HubClient("http://hub.test");
  let created: Record<string, unknown> | undefined;
  hub.getCollab = () =>
    Promise.resolve({
      collab: {
        id: "c1",
        name: "sprint",
        encryption_mode: "app_envelope",
        lists: [
          { id: "l-backlog", name: "Backlog", position: 0 },
          { id: "l-doing", name: "Doing", position: 1 },
        ],
      } as CollabView,
    });
  hub.createThread = (_token, input) => {
    created = input as unknown as Record<string, unknown>;
    return Promise.resolve({
      thread: meta({
        id: "th-card",
        collab_id: "c1",
        lane_id: "l-doing",
        from: "u@acme/chatgpt",
      }),
      message_id: "m-card",
    });
  };
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 26,
      method: "tools/call",
      params: {
        name: "create_card",
        arguments: {
          collab_id: "c1",
          title: "Ship invites",
          lane: "Doing",
        },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError ?? false, false);
  const body = JSON.parse(result.content[0].text);
  assertEquals(body.thread_id, "th-card");
  assertEquals(body.collab_id, "c1");
  assertEquals(created?.collab_id, "c1");
  assertEquals(created?.lane_id, "Doing");
  assertEquals(created?.to, "u@acme");
});

Deno.test("create_card passes assigned_to without retargeting wrap", async () => {
  const hub = new HubClient("http://hub.test");
  let created: Record<string, unknown> | undefined;
  hub.getCollab = () =>
    Promise.resolve({
      collab: {
        id: "c1",
        name: "sprint",
        encryption_mode: "app_envelope",
        lists: [{ id: "l-backlog", name: "Backlog", position: 0 }],
        steerers: [{ user_id: "u-bob", handle: "bob@acme" }],
        roster: [{ user_id: "u-bob", agent_id: "a1", address: "bob@acme/claude" }],
      } as CollabView,
    });
  hub.createThread = (_token, input) => {
    created = input as unknown as Record<string, unknown>;
    return Promise.resolve({
      thread: meta({
        id: "th-card",
        collab_id: "c1",
        assigned_to: "bob@acme/claude",
        from: "u@acme/chatgpt",
      }),
      message_id: "m-card",
    });
  };
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 30,
      method: "tools/call",
      params: {
        name: "create_card",
        arguments: {
          collab_id: "c1",
          title: "Ship invites",
          assigned_to: "bob@acme/claude",
          tags: ["launch"],
          due_on: "2026-09-01",
          checklist: [{ text: "Draft copy" }],
        },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError ?? false, false);
  assertEquals(created?.collab_id, "c1");
  assertEquals(created?.assigned_to, "bob@acme/claude");
  assertEquals(created?.to, "u@acme");
  assertEquals((created?.tags as string[])[0], "launch");
  assertEquals(created?.due_on, "2026-09-01");
});

Deno.test("create_card is forbidden for non-participants", async () => {
  const hub = new HubClient("http://hub.test");
  hub.getCollab = () =>
    Promise.reject(new HubClientError("Not a collab member", 403));
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 27,
      method: "tools/call",
      params: {
        name: "create_card",
        arguments: { collab_id: "c-secret", title: "Nope" },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("403"), true);
});

Deno.test("create_card refuses e2e collab on hosted MCP", async () => {
  const hub = new HubClient("http://hub.test");
  hub.getCollab = () =>
    Promise.resolve({
      collab: {
        id: "c-e2e",
        name: "sealed",
        encryption_mode: "e2e",
      } as CollabView,
    });
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 28,
      method: "tools/call",
      params: {
        name: "create_card",
        arguments: { collab_id: "c-e2e", title: "Secret" },
      },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("E2E"), true);
});

Deno.test("create_card requires collab_id and title", async () => {
  const hub = new HubClient("http://hub.test");
  const res = await handleMcpRequest(
    {
      jsonrpc: "2.0",
      id: 29,
      method: "tools/call",
      params: { name: "create_card", arguments: { collab_id: "c1" } },
    },
    { session: fakeSession, serverVersion: "0.1.0", hub },
  );
  const result = res!.result as { content: Array<{ text: string }>; isError?: boolean };
  assertEquals(result.isError, true);
  assertEquals(result.content[0].text.includes("title"), true);
});
