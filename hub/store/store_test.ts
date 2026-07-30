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

Deno.test("any participant can close; delete removes inbox", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    const { thread } = await store.createThread(aliceAuth, {
      to: "bob@acme",
      envelope: sampleEnvelope("del"),
    });
    await store.closeThread(bobAuth, thread.id);
    assertEquals((await store.listThreads(bobAuth, "closed")).threads.length, 1);

    await store.deleteThread(bobAuth, thread.id);
    assertEquals((await store.listThreads(bobAuth)).threads.length, 0);
    // Sender still has an inbox row, but thread body is intact until they delete.
    assertEquals((await store.listThreads(aliceAuth, "closed")).threads.length, 1);

    await store.deleteThread(aliceAuth, thread.id);
    assertEquals((await store.listThreads(aliceAuth)).threads.length, 0);
  });
});

Deno.test("sender purge clears every org member inbox", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth, carolAuth } = await setupOrgWithUsers(store);
    const { thread } = await store.createThread(aliceAuth, {
      to: "@all@acme",
      envelope: sampleEnvelope("purge-all"),
    });
    assertEquals((await store.listThreads(bobAuth, "needs_action")).threads.length, 1);
    assertEquals((await store.listThreads(carolAuth, "needs_action")).threads.length, 1);

    await store.deleteThread(aliceAuth, thread.id);

    assertEquals((await store.listThreads(aliceAuth)).threads.length, 0);
    assertEquals((await store.listThreads(bobAuth)).threads.length, 0);
    assertEquals((await store.listThreads(carolAuth)).threads.length, 0);
    await assertRejects(
      () => store.deleteThread(bobAuth, thread.id),
      HubError,
      "Not a thread participant",
    );
  });
});

Deno.test("orphan inbox dismisses when thread body is gone", async () => {
  const kv = await Deno.openKv(":memory:");
  const { store } = await createStoreWithTestAuth(kv);
  try {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    const { thread } = await store.createThread(aliceAuth, {
      to: "bob@acme",
      envelope: sampleEnvelope("orphan"),
    });
    // Pre-fix shape: body deleted, recipient inbox left behind.
    await kv.delete(["threads", thread.id]);
    assertEquals((await store.listThreads(bobAuth)).threads.length, 0);

    await store.deleteThread(bobAuth, thread.id);
    await assertRejects(
      () => store.deleteThread(bobAuth, thread.id),
      HubError,
      "Not a thread participant",
    );
  } finally {
    kv.close();
  }
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

Deno.test("sole-member @all delivers to self", async () => {
  await withTestStore(async ({ store }) => {
    const { user } = await store.createOrgWithAdmin(
      { sub: "auth0|solo", email: "solo@tbh.co" },
      { slug: "tbhco", name: "TBH", handle: "solo@tbhco" },
    );
    const auth = store.authContextFromUser(user);
    await store.registerDevice(auth, { pubkey: "solo-pk", platform: "macos" });
    await store.registerAgent(auth, { slug: "cursor" });
    const { thread } = await store.createThread(auth, {
      to: "@all@tbhco",
      envelope: sampleEnvelope("solo-all"),
      from_agent: "cursor",
    });
    assertEquals(thread.kind, "broadcast");
    assertEquals(thread.audience, "@all@tbhco");
    // Self-delivery stays Waiting for the human inbox (agent MCP remaps).
    assertEquals((await store.listThreads(auth, "needs_action")).threads.length, 0);
    assertEquals((await store.listThreads(auth, "open")).threads[0]?.your_status, "replied");
  });
});

Deno.test("self agent handoff allowed", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    await store.registerAgent(aliceAuth, { slug: "claude" });
    const { thread } = await store.createThread(aliceAuth, {
      to: "alice@acme/claude",
      envelope: sampleEnvelope("self-hand"),
      from_agent: "cursor",
    });
    assertEquals(thread.from, "alice@acme/cursor");
    assertEquals(thread.audience, "alice@acme/claude");
    // Outbound self-collab is Waiting, not Needs you.
    assertEquals((await store.listThreads(aliceAuth, "needs_action")).threads.length, 0);
    const listed = await store.listThreads(aliceAuth, "open");
    assertEquals(listed.threads[0]?.your_status, "replied");
    const got = await store.getThread(aliceAuth, thread.id);
    assertEquals(got.thread.your_status, "replied");
    // Own agents can still reply (role allows recipient).
    await store.postReply(aliceAuth, thread.id, {
      envelope: sampleEnvelope("self-reply"),
      from_agent: "claude",
    });
    assertEquals((await store.getThread(aliceAuth, thread.id)).messages.length, 2);
    // Reply must not clobber Waiting back to Needs you on the shared inbox key.
    assertEquals((await store.getThread(aliceAuth, thread.id)).thread.your_status, "replied");
    assertEquals((await store.listThreads(aliceAuth, "needs_action")).threads.length, 0);
  });
});

Deno.test("reply from_agent=claude sets from_handle /claude", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    await store.registerAgent(bobAuth, { slug: "cursor" });
    const { thread } = await store.createThread(aliceAuth, {
      to: "bob@acme/claude",
      envelope: sampleEnvelope("to-bob"),
      from_agent: "cursor",
    });
    await store.postReply(bobAuth, thread.id, {
      envelope: sampleEnvelope("bob-claude-reply"),
      from_agent: "claude",
    });
    const detail = await store.getThread(aliceAuth, thread.id);
    const reply = detail.messages.find((m) => m.id !== detail.messages[0]?.id) ?? detail.messages.at(-1);
    assertExists(reply);
    assertEquals(reply!.from_handle, "bob@acme/claude");
    assertEquals(reply!.from_handle.endsWith("/claude"), true);
  });
});

Deno.test("bare self-send allowed when from_agent is not default", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    await store.registerAgent(aliceAuth, { slug: "claude" });
    // default is cursor (first registered); send from claude → bare → cursor
    const { thread } = await store.createThread(aliceAuth, {
      to: "alice@acme",
      envelope: sampleEnvelope("bare-self"),
      from_agent: "claude",
    });
    assertEquals(thread.audience, "alice@acme/cursor");
    assertEquals(thread.from, "alice@acme/claude");
  });
});

Deno.test("same-agent self-loop rejected", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    const err = await assertRejects(
      () => store.createThread(aliceAuth, {
        to: "alice@acme/cursor",
        envelope: sampleEnvelope("noop"),
        from_agent: "cursor",
      }),
      HubError,
    );
    assertEquals((err as HubError).code, "invalid_recipient");
    assertEquals((err as Error).message.includes("same agent"), true);

    const bareErr = await assertRejects(
      () => store.createThread(aliceAuth, {
        to: "alice@acme",
        envelope: sampleEnvelope("bare-noop"),
        from_agent: "cursor",
      }),
      HubError,
    );
    assertEquals((bareErr as HubError).code, "invalid_recipient");

    const shorthandErr = await assertRejects(
      () => store.createThread(aliceAuth, {
        to: "@cursor",
        envelope: sampleEnvelope("shorthand-noop"),
        from_agent: "cursor",
      }),
      HubError,
    );
    assertEquals((shorthandErr as HubError).code, "invalid_recipient");
  });
});

Deno.test("@claude shorthand expands to self agent", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    await store.registerAgent(aliceAuth, { slug: "claude" });
    const { thread } = await store.createThread(aliceAuth, {
      to: "@claude",
      envelope: sampleEnvelope("shorthand"),
      from_agent: "cursor",
    });
    assertEquals(thread.kind, "direct");
    assertEquals(thread.from, "alice@acme/cursor");
    assertEquals(thread.audience, "alice@acme/claude");
    assertEquals(thread.audience_wire_path, "acme/alice/claude");
    assertEquals((await store.listThreads(aliceAuth, "needs_action")).threads.length, 0);
    assertEquals((await store.listThreads(aliceAuth, "open")).threads[0]?.your_status, "replied");
  });
});

Deno.test("unknown @slug rejected", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    const err = await assertRejects(
      () => store.createThread(aliceAuth, {
        to: "@research",
        envelope: sampleEnvelope("missing"),
        from_agent: "cursor",
      }),
      HubError,
    );
    assertEquals((err as HubError).code, "unknown_agent");
  });
});

Deno.test("bare @all fans out to my agents", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    await store.registerAgent(aliceAuth, { slug: "claude" });
    const { thread } = await store.createThread(aliceAuth, {
      to: "@all",
      envelope: sampleEnvelope("my-agents"),
      from_agent: "cursor",
    });
    assertEquals(thread.kind, "broadcast");
    assertEquals(thread.audience, "@all");
    assertEquals(thread.audience_agent_id, undefined);
    // Human inbox: Waiting on own agents (not Needs you).
    assertEquals((await store.listThreads(aliceAuth, "needs_action")).threads.length, 0);
    assertEquals((await store.listThreads(aliceAuth, "open")).threads[0]?.your_status, "replied");
    // Org members do not receive bare @all (that's @all@org).
    assertEquals((await store.listThreads(bobAuth, "needs_action")).threads.length, 0);
  });
});

Deno.test("@all@org still fans out to other members", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth, carolAuth } = await setupOrgWithUsers(store);
    const { thread } = await store.createThread(aliceAuth, {
      to: "@all@acme",
      envelope: sampleEnvelope("org-all"),
      from_agent: "cursor",
    });
    assertEquals(thread.audience, "@all@acme");
    assertEquals((await store.listThreads(bobAuth, "needs_action")).threads.length, 1);
    assertEquals((await store.listThreads(carolAuth, "needs_action")).threads.length, 1);
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

Deno.test("message upvotes toggle per agent", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    const { thread } = await store.createThread(aliceAuth, {
      to: "bob@acme",
      envelope: sampleEnvelope(),
    });
    const detail = await store.getThread(bobAuth, thread.id);
    const msgId = detail.messages[0]!.id;
    const bobClaude = (await store.listAgents(bobAuth)).agents.find((a) => a.slug === "claude");
    assertExists(bobClaude);

    const first = await store.toggleMessageUpvote(bobAuth, thread.id, msgId, {
      from_agent: "claude",
    });
    assertEquals(first.upvoted, true);
    assertEquals(first.upvotes.count, 1);
    assertEquals(first.upvotes.your_upvotes, [bobClaude.id]);

    const again = await store.toggleMessageUpvote(bobAuth, thread.id, msgId, {
      from_agent: "claude",
    });
    assertEquals(again.upvoted, false);
    assertEquals(again.upvotes.count, 0);

    const enriched = await store.getThread(bobAuth, thread.id);
    assertEquals(enriched.messages[0]!.upvotes?.count, 0);
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
