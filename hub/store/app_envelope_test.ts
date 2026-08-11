import { assertEquals, assertExists, assertRejects } from "jsr:@std/assert@1";
import {
  APP_ENVELOPE_RETENTION_DAYS,
  APP_ENVELOPE_RETENTION_MS,
  assertExclusiveWireUnit,
  isEnterpriseAgentStub,
  isExternalContactStub,
  resolveThreadEncryptionMode,
  resetAppEnvelopeKeyCache,
  sealAppEnvelope,
  openAppEnvelope,
  buildAppEnvelopeRecord,
  retentionExpiresAt,
} from "./app_envelope.ts";
import { HubError } from "./errors.ts";
import {
  createStoreWithTestAuth,
  type HubStore,
} from "./store.ts";
import type { Agent, Auth0Claims, Envelope } from "./types.ts";
import { APP_ENVELOPE_RETENTION_MS as RETENTION_FROM_TYPES } from "./types.ts";

function sampleEnvelope(tag = "a"): Envelope {
  return {
    version: 1,
    content_nonce: Array(12).fill(0),
    ciphertext: Array.from(new TextEncoder().encode(`cipher-${tag}`)),
    wraps: [{ recipient: Array(32).fill(1), ephemeral_public: Array(32).fill(2), boxed_cek: [4, 5, 6] }],
  };
}

function sampleAgent(overrides: Partial<Agent> & Pick<Agent, "id" | "slug" | "transport">): Agent {
  return {
    user_id: "u",
    created_at: new Date().toISOString(),
    visibility: "private",
    trust_tier: "org",
    billing: null,
    mcp_endpoint: overrides.transport === "mcp" ? "https://mcp.mutande.online" : null,
    capabilities: null,
    capabilities_updated_at: null,
    ...overrides,
  };
}

async function withTestStore(
  fn: (ctx: {
    store: HubStore;
    kv: Deno.Kv;
    signToken: (c: Auth0Claims) => Promise<string>;
  }) => Promise<void>,
) {
  const kv = await Deno.openKv(":memory:");
  const { store, signToken } = await createStoreWithTestAuth(kv);
  try {
    await fn({ store, kv, signToken });
  } finally {
    kv.close();
  }
}

async function setupOrgWithUsers(store: HubStore) {
  const { user: alice } = await store.createOrgWithAdmin(
    { sub: "auth0|alice", email: "alice@example.com" },
    { slug: "acme", name: "Acme", handle: "alice@acme" },
  );
  const inv1 = await store.createInvite(store.authContextFromUser(alice));
  const { user: bob } = await store.joinOrg(
    { sub: "auth0|bob", email: "bob@example.com" },
    { invite_code: inv1.code, handle: "bob@acme" },
  );
  await store.registerDevice(store.authContextFromUser(alice), {
    pubkey: "alice-pk",
    platform: "macos",
  });
  await store.registerDevice(store.authContextFromUser(bob), {
    pubkey: "bob-pk",
    platform: "macos",
  });
  await store.registerAgent(store.authContextFromUser(alice), { slug: "cursor" });
  await store.registerAgent(store.authContextFromUser(bob), { slug: "claude" });
  return {
    aliceAuth: store.authContextFromUser(alice),
    bobAuth: store.authContextFromUser(bob),
  };
}

Deno.test("L2 retention constants are 30 days", () => {
  assertEquals(APP_ENVELOPE_RETENTION_DAYS, 30);
  assertEquals(APP_ENVELOPE_RETENTION_MS, 30 * 24 * 60 * 60 * 1000);
  assertEquals(RETENTION_FROM_TYPES, APP_ENVELOPE_RETENTION_MS);
  const created = "2026-01-01T00:00:00.000Z";
  assertEquals(retentionExpiresAt(created), "2026-01-31T00:00:00.000Z");
});

Deno.test("L2 resolveThreadEncryptionMode: sidecar→sidecar is e2e", () => {
  const sender = sampleAgent({ id: "a", slug: "cursor", transport: "sidecar" });
  const audience = sampleAgent({ id: "b", slug: "claude", transport: "sidecar" });
  assertEquals(resolveThreadEncryptionMode({ sender, audience }), "e2e");
});

Deno.test("L2 resolveThreadEncryptionMode: any mcp → app_envelope", () => {
  const sidecar = sampleAgent({ id: "a", slug: "cursor", transport: "sidecar" });
  const mcp = sampleAgent({ id: "b", slug: "chatgpt", transport: "mcp" });
  assertEquals(resolveThreadEncryptionMode({ sender: sidecar, audience: mcp }), "app_envelope");
  assertEquals(resolveThreadEncryptionMode({ sender: mcp, audience: sidecar }), "app_envelope");
  assertEquals(resolveThreadEncryptionMode({ sender: mcp, audience: mcp }), "app_envelope");
});

Deno.test("L2 L3/L4 flags force app_envelope", () => {
  const sidecar = sampleAgent({ id: "a", slug: "cursor", transport: "sidecar" });
  assertEquals(isExternalContactStub("eve@rival"), false);
  assertEquals(isEnterpriseAgentStub(sidecar), false);
  assertEquals(
    resolveThreadEncryptionMode({
      sender: sidecar,
      audience: sidecar,
      hasExternalContact: true,
    }),
    "app_envelope",
  );
  assertEquals(
    resolveThreadEncryptionMode({
      sender: sidecar,
      audience: sidecar,
      hasEnterpriseAgent: true,
    }),
    "app_envelope",
  );
  const enterprise = sampleAgent({
    id: "e",
    slug: "assistant",
    transport: "mcp",
    trust_tier: "enterprise",
  });
  assertEquals(isEnterpriseAgentStub(enterprise), true);
});

Deno.test("L2 never mix envelope and app_envelope in one wire unit", () => {
  assertEquals(assertExclusiveWireUnit({ envelope: sampleEnvelope() }), "e2e");
  assertEquals(
    assertExclusiveWireUnit({ app_envelope: { version: 1, notes: "hi" } }),
    "app_envelope",
  );
  assertThrowsMix();
  function assertThrowsMix() {
    try {
      assertExclusiveWireUnit({
        envelope: sampleEnvelope(),
        app_envelope: { version: 1 },
      });
      throw new Error("expected mix rejection");
    } catch (e) {
      assertEquals(e instanceof HubError, true);
      assertEquals((e as HubError).code, "invalid_argument");
    }
  }
  try {
    assertExclusiveWireUnit({});
    throw new Error("expected empty rejection");
  } catch (e) {
    assertEquals(e instanceof HubError, true);
  }
});

Deno.test("L2 create: all-sidecar stays e2e", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    const { thread } = await store.createThread(aliceAuth, {
      to: "bob@acme",
      envelope: sampleEnvelope("e2e"),
    });
    assertEquals(thread.encryption_mode, "e2e");
    assertEquals(thread.downgrade_point, undefined);

    const got = await store.getThread(bobAuth, thread.id);
    assertEquals(got.thread.encryption_mode, "e2e");
    assertExists(got.messages[0].envelope);
    assertEquals(got.messages[0].app_envelope, undefined);
  });
});

Deno.test("L2 create: web audience → app_envelope", async () => {
  await withTestStore(async ({ store, kv }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    const mcp = await store.connectAgent(aliceAuth, "mcp", { slug: "webslot" });
    await store.setTransportDefault(aliceAuth, { slug: "webslot", transport: "mcp" });

    const { thread, message_id } = await store.createThread(bobAuth, {
      to: "alice@acme/webslot",
      app_envelope: { version: 1, subject: "hi", notes: "from bob" },
      from_agent: "claude",
    });
    assertEquals(thread.encryption_mode, "app_envelope");
    assertEquals(thread.audience_agent_id, mcp.id);

    const stored = await kv.get(["app_envelopes", thread.id, message_id]);
    assertExists(stored.value);

    const got = await store.getThread(aliceAuth, thread.id);
    assertEquals(got.messages[0].app_envelope?.notes, "from bob");
    assertEquals(got.messages[0].envelope, undefined);
  });
});

Deno.test("L2 create: web sender can only start app_envelope", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    await store.connectAgent(aliceAuth, "mcp", { slug: "webme" });
    await store.setTransportDefault(aliceAuth, { slug: "webme", transport: "mcp" });

    const { thread } = await store.createThread(aliceAuth, {
      to: "bob@acme",
      app_envelope: { version: 1, notes: "web→sidecar" },
      from_agent: "webme",
    });
    assertEquals(thread.encryption_mode, "app_envelope");

    await assertRejects(
      () =>
        store.createThread(aliceAuth, {
          to: "bob@acme",
          envelope: sampleEnvelope("nope"),
          from_agent: "webme",
        }),
      HubError,
    );
  });
});

Deno.test("L2 reject wrong wire unit for resolved mode", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    await store.connectAgent(aliceAuth, "mcp", { slug: "webslot" });

    // mcp audience requires app_envelope — envelope rejected
    await assertRejects(
      () =>
        store.createThread(bobAuth, {
          to: "alice@acme/webslot",
          envelope: sampleEnvelope("mix"),
          from_agent: "claude",
        }),
      HubError,
    );

    // sidecar→sidecar requires envelope — app_envelope rejected
    await assertRejects(
      () =>
        store.createThread(bobAuth, {
          to: "alice@acme/cursor",
          app_envelope: { version: 1, notes: "wrong" },
          from_agent: "claude",
        }),
      HubError,
    );

    // both in one request
    await assertRejects(
      () =>
        store.createThread(bobAuth, {
          to: "alice@acme/cursor",
          envelope: sampleEnvelope(),
          app_envelope: { version: 1 },
          from_agent: "claude",
        }),
      HubError,
    );
  });
});

Deno.test("L2 fetchAppMessages auth + e2e rejection", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    const mcp = await store.connectAgent(aliceAuth, "mcp", { slug: "webslot" });

    const { thread: e2e } = await store.createThread(aliceAuth, {
      to: "bob@acme",
      envelope: sampleEnvelope("e2e"),
    });
    await assertRejects(
      () => store.fetchAppMessages(bobAuth, e2e.id),
      HubError,
    );

    const { thread: app } = await store.createThread(bobAuth, {
      to: "alice@acme/webslot",
      app_envelope: { version: 1, notes: "pull-me" },
      from_agent: "claude",
    });

    const pulled = await store.fetchAppMessages(aliceAuth, app.id, {
      agent_id: mcp.id,
    });
    assertEquals(pulled.messages[0].app_envelope?.notes, "pull-me");
    assertEquals(pulled.messages[0].envelope, undefined);

    // Foreign agent_id rejected
    const bobAgent = (await store.listAgents(bobAuth)).agents[0];
    await assertRejects(
      () =>
        store.fetchAppMessages(aliceAuth, app.id, { agent_id: bobAgent.id }),
      HubError,
    );

    // Non-participant rejected
    const { user: carol } = await store.createOrgWithAdmin(
      { sub: "auth0|carol", email: "carol@other.test" },
      { slug: "other", handle: "carol@other" },
    );
    await assertRejects(
      () => store.fetchAppMessages(store.authContextFromUser(carol), app.id),
      HubError,
    );
  });
});

Deno.test("L2 deleteThread purges app_envelope payloads", async () => {
  await withTestStore(async ({ store, kv }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    await store.connectAgent(aliceAuth, "mcp", { slug: "webslot" });

    const { thread, message_id } = await store.createThread(bobAuth, {
      to: "alice@acme/webslot",
      app_envelope: { version: 1, notes: "bye" },
      from_agent: "claude",
    });
    assertExists((await kv.get(["app_envelopes", thread.id, message_id])).value);

    await store.postReply(aliceAuth, thread.id, {
      app_envelope: { version: 1, notes: "reply" },
      from_agent: "webslot",
    });

    await store.deleteThread(bobAuth, thread.id);
    assertEquals((await kv.get(["app_envelopes", thread.id, message_id])).value, null);

    const leftover = kv.list({ prefix: ["app_envelopes", thread.id] });
    let count = 0;
    for await (const _ of leftover) count++;
    assertEquals(count, 0);
  });
});

Deno.test("L2 web cannot reply to E2E thread without downgrade approve", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    await store.connectAgent(bobAuth, "mcp", { slug: "webclaude" });

    const { thread } = await store.createThread(aliceAuth, {
      to: "bob@acme/claude",
      envelope: sampleEnvelope("e2e"),
    });
    assertEquals(thread.encryption_mode, "e2e");

    await assertRejects(
      () =>
        store.postReply(bobAuth, thread.id, {
          app_envelope: { version: 1, notes: "nope" },
          from_agent: "webclaude",
        }),
      HubError,
      "downgrade",
    );
  });
});

Deno.test("L2 seal/open round-trip with APP_ENVELOPE_KEY", async () => {
  const keyBytes = crypto.getRandomValues(new Uint8Array(32));
  let b64 = "";
  for (const b of keyBytes) b64 += String.fromCharCode(b);
  Deno.env.set("APP_ENVELOPE_KEY", btoa(b64));
  resetAppEnvelopeKeyCache();
  try {
    const sealed = await sealAppEnvelope({ version: 1, notes: "secret" });
    assertEquals(sealed.at_rest, "aes-gcm");
    const record = await buildAppEnvelopeRecord({
      threadId: "t",
      messageId: "m",
      fromUserId: "u",
      createdAt: new Date().toISOString(),
      payload: { version: 1, notes: "secret" },
    });
    const opened = await openAppEnvelope(record);
    assertEquals(opened.notes, "secret");
  } finally {
    Deno.env.delete("APP_ENVELOPE_KEY");
    resetAppEnvelopeKeyCache();
  }
});

Deno.test("L2 plaintext-at-rest interim when key unset", async () => {
  Deno.env.delete("APP_ENVELOPE_KEY");
  resetAppEnvelopeKeyCache();
  const sealed = await sealAppEnvelope({ version: 1, notes: "plain" });
  assertEquals(sealed.at_rest, "plaintext");
  assertEquals(JSON.parse(sealed.body).notes, "plain");
});
