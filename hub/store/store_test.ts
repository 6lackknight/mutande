import { assertEquals, assertExists, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { HubError } from "./errors.ts";
import { HubStore, createStore, createStoreWithTestAuth } from "./store.ts";
import type { Auth0Claims, Envelope } from "./types.ts";
import { MAX_ENVELOPE_BYTES, ORG_BLOB_QUOTA_BYTES } from "./types.ts";

function sampleEnvelope(tag = "a"): Envelope {
  return {
    version: 1,
    content_nonce: Array(12).fill(0),
    ciphertext: Array.from(new TextEncoder().encode(`cipher-${tag}`)),
    wraps: [{ recipient: Array(32).fill(1), ephemeral_public: Array(32).fill(2), boxed_cek: [4, 5, 6] }],
  };
}

async function withTestStore(fn: (ctx: { store: HubStore; signToken: (c: Auth0Claims) => Promise<string> }) => Promise<void>) {
  const kv = await Deno.openKv(":memory:");
  const { store, signToken } = await createStoreWithTestAuth(kv);
  try { await fn({ store, signToken }); } finally { kv.close(); }
}

async function setupOrgWithUsers(store: HubStore) {
  const { user: alice } = await store.createOrgWithAdmin(
    { sub: "auth0|alice", email: "alice@example.com" },
    { slug: "acme", name: "Acme", handle: "alice@acme" },
  );
  const inv1 = await store.createInvite(store.authContextFromUser(alice));
  const { user: bob } = await store.joinOrg({ sub: "auth0|bob", email: "bob@example.com" }, { invite_code: inv1.code, handle: "bob@acme" });
  const inv2 = await store.createInvite(store.authContextFromUser(alice));
  const { user: carol } = await store.joinOrg({ sub: "auth0|carol", email: "carol@example.com" }, { invite_code: inv2.code, handle: "carol@acme" });
  await store.registerDevice(store.authContextFromUser(alice), { pubkey: "alice-pk", platform: "macos" });
  await store.registerDevice(store.authContextFromUser(bob), { pubkey: "bob-pk", platform: "macos" });
  await store.registerDevice(store.authContextFromUser(carol), { pubkey: "carol-pk", platform: "ios" });
  await store.registerAgent(store.authContextFromUser(alice), { slug: "cursor" });
  await store.registerAgent(store.authContextFromUser(bob), { slug: "claude" });
  await store.registerAgent(store.authContextFromUser(carol), { slug: "chatgpt" });
  return {
    aliceAuth: store.authContextFromUser(alice),
    bobAuth: store.authContextFromUser(bob),
    carolAuth: store.authContextFromUser(carol),
  };
}

Deno.test("create org with admin", async () => {
  await withTestStore(async ({ store }) => {
    const claims = { sub: "auth0|founder", email: "founder@startup.io" };
    const { user } = await store.createOrgWithAdmin(claims, { slug: "startup", name: "Startup" });
    assertEquals(user.role, "org_admin");
    assertEquals((await store.getMe(claims)).onboarded, true);
  });
});

Deno.test("join org default handle", async () => {
  await withTestStore(async ({ store }) => {
    const { user: admin } = await store.createOrgWithAdmin({ sub: "auth0|admin", email: "admin@co.test" }, { slug: "co", name: "Co" });
    const invite = await store.createInvite(store.authContextFromUser(admin));
    const { user } = await store.joinOrg({ sub: "auth0|member", email: "member.person@co.test" }, { invite_code: invite.code });
    assertEquals(user.handle, "member.person@co");
    assertEquals(user.role, "member");
  });
});

Deno.test("contacts expose device pubkeys", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    assertEquals((await store.listContacts(aliceAuth)).contacts.find((c) => c.handle === "bob@acme")?.pubkey, "bob-pk");
    assertEquals((await store.listContacts(bobAuth)).contacts.find((c) => c.handle === "alice@acme")?.pubkey, "alice-pk");
  });
});

Deno.test("thread inbox filters", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    const { thread } = await store.createThread(aliceAuth, { to: "bob@acme", envelope: sampleEnvelope() });
    assertEquals((await store.listThreads(bobAuth, "needs_action")).threads.length, 1);
    await store.postReply(bobAuth, thread.id, { envelope: sampleEnvelope("r") });
    await store.closeThread(aliceAuth, thread.id);
    assertEquals((await store.listThreads(aliceAuth, "closed")).threads.length, 1);
  });
});

Deno.test("broadcast fan-out", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth, carolAuth } = await setupOrgWithUsers(store);
    const { thread } = await store.createThread(aliceAuth, { to: "@all@acme", envelope: sampleEnvelope("b") });
    for (const auth of [bobAuth, carolAuth]) assertEquals((await store.listThreads(auth, "needs_action")).threads.length, 1);
    await store.postReply(bobAuth, thread.id, { envelope: sampleEnvelope("br") });
    assertEquals((await store.getThread(aliceAuth, thread.id)).messages.length, 2);
  });
});

Deno.test("draft CRUD", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    const draft = await store.createDraft(aliceAuth, sampleEnvelope("d"));
    await store.updateDraft(aliceAuth, draft.id, sampleEnvelope("d2"));
    await store.deleteDraft(aliceAuth, draft.id);
    assertEquals((await store.listDrafts(aliceAuth)).drafts.length, 0);
  });
});

Deno.test("cross-org rejected", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    await store.createOrgWithAdmin({ sub: "auth0|eve", email: "eve@rival.com" }, { slug: "rival", name: "Rival" });
    await assertRejects(() => store.createThread(aliceAuth, { to: "eve@rival", envelope: sampleEnvelope() }));
  });
});

Deno.test("agent-scoped thread addressing", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    const { thread } = await store.createThread(aliceAuth, {
      to: "bob@acme/claude",
      envelope: sampleEnvelope("agent"),
      from_agent: "cursor",
    });
    assertEquals(thread.from, "alice@acme/cursor");
    assertEquals(thread.audience, "bob@acme/claude");
    assertEquals(thread.audience_wire_path, "acme/bob/claude");
    assertEquals((await store.listThreads(bobAuth, "needs_action")).threads.length, 1);
  });
});

Deno.test("unknown agent rejected", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    await assertRejects(() => store.createThread(aliceAuth, {
      to: "bob@acme/unknown",
      envelope: sampleEnvelope(),
    }));
  });
});

Deno.test("rename agent slug", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    const { agents } = await store.listAgents(aliceAuth);
    const cursor = agents.find((a) => a.slug === "cursor");
    assertExists(cursor);
    const renamed = await store.renameAgent(aliceAuth, cursor!.id, { slug: "codex" });
    assertEquals(renamed.slug, "codex");
    assertEquals(renamed.id, cursor!.id);
    const again = await store.listAgents(aliceAuth);
    assertEquals(again.agents.some((a) => a.slug === "codex"), true);
    assertEquals(again.agents.some((a) => a.slug === "cursor"), false);

    const err = await assertRejects(
      () => store.createThread(bobAuth, {
        to: "alice@acme/cursor",
        envelope: sampleEnvelope("renamed"),
        from_agent: "claude",
      }),
      HubError,
    );
    assertEquals((err as HubError).code, "agent_renamed");
    assertEquals((err as Error).message.includes("codex"), true);

    const { thread } = await store.createThread(bobAuth, {
      to: "alice@acme/codex",
      envelope: sampleEnvelope("new-slug"),
      from_agent: "claude",
    });
    assertEquals(thread.audience, "alice@acme/codex");
    assertEquals(thread.audience_agent_id, cursor!.id);
  });
});

Deno.test("router rules most specific wins", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    await store.registerAgent(aliceAuth, { slug: "research" });
    const { agents, default_agent_id } = await store.listAgents(aliceAuth);
    const cursor = agents.find((a) => a.slug === "cursor");
    const research = agents.find((a) => a.slug === "research");
    assertExists(cursor);
    assertExists(research);
    assertEquals(default_agent_id, cursor!.id);

    const router = await store.getRouter(aliceAuth);
    assertEquals(router.default_agent_id, cursor!.id);
    assertEquals(router.rules.some((r) => r.match_slug === "research"), true);

    // Remap research → cursor agent_id (custom rule).
    await store.setRouter(aliceAuth, {
      rules: [
        { match_slug: "cursor", agent_id: cursor!.id },
        { match_slug: "research", agent_id: cursor!.id },
      ],
    });

    const { thread } = await store.createThread(bobAuth, {
      to: "alice@acme/research",
      envelope: sampleEnvelope("remap"),
      from_agent: "claude",
    });
    assertEquals(thread.audience_agent_id, cursor!.id);

    // Bare → default.
    const { thread: bare } = await store.createThread(bobAuth, {
      to: "alice@acme",
      envelope: sampleEnvelope("bare"),
      from_agent: "claude",
    });
    assertEquals(bare.audience_agent_id, cursor!.id);
    assertEquals(bare.audience, "alice@acme/cursor");
  });
});

Deno.test("oversized envelope rejected", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    await assertRejects(() => store.createThread(aliceAuth, {
      to: "bob@acme",
      envelope: { version: 1, content_nonce: [], ciphertext: Array(MAX_ENVELOPE_BYTES).fill(1), wraps: [] },
    }));
  });
});

Deno.test("blob quota", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    await store.createUploadUrl(aliceAuth, 1024);
    await assertRejects(() => store.createUploadUrl(aliceAuth, ORG_BLOB_QUOTA_BYTES));
  });
});

Deno.test("admin invites", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    const created = await store.createInvite(aliceAuth);
    assertEquals((await store.listInvites(aliceAuth)).invites.some((i) => i.code === created.code), true);
  });
});

Deno.test("double onboarding rejected", async () => {
  await withTestStore(async ({ store }) => {
    const claims = { sub: "auth0|once", email: "once@test.com" };
    await store.createOrgWithAdmin(claims, { slug: "once", name: "Once" });
    await assertRejects(() => store.createOrgWithAdmin(claims, { slug: "other", name: "Other" }), HubError);
  });
});

Deno.test("createStore requires Auth0 on deploy", async () => {
  const kv = await Deno.openKv(":memory:");
  const prev = Deno.env.get("DENO_DEPLOYMENT_ID");
  Deno.env.set("DENO_DEPLOYMENT_ID", "x");
  Deno.env.delete("AUTH0_DOMAIN");
  Deno.env.delete("AUTH0_AUDIENCE");
  try {
    assertThrows(() => createStore(kv), Error, "AUTH0_DOMAIN and AUTH0_AUDIENCE must be set in production");
  } finally {
    if (prev === undefined) Deno.env.delete("DENO_DEPLOYMENT_ID"); else Deno.env.set("DENO_DEPLOYMENT_ID", prev);
    kv.close();
  }
});

Deno.test("verifyAuth0 token helper", async () => {
  await withTestStore(async ({ store, signToken }) => {
    const claims = await store.verifyAuth0Token(await signToken({ sub: "auth0|tok", email: "tok@test.com" }));
    assertEquals(claims.sub, "auth0|tok");
  });
});
