import { assertEquals, assertExists, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { HubError } from "./errors.ts";
import {
  HubStore,
  agentCapabilitiesFresh,
  createStore,
  createStoreWithTestAuth,
} from "./store.ts";
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

Deno.test("update profile display name and avatar", async () => {
  await withTestStore(async ({ store }) => {
    const claims = { sub: "auth0|pat", email: "pat@co.test" };
    await store.createOrgWithAdmin(claims, { slug: "patco", name: "PatCo" });

    const avatar = `data:image/jpeg;base64,${btoa("tiny")}`;
    let me = await store.updateProfile(claims, {
      display_name: "  Pat Jones  ",
      avatar_url: avatar,
    });
    assertEquals(me.user?.display_name, "Pat Jones");
    assertEquals(me.user?.avatar_url, avatar);

    // Omitted fields stay unchanged; empty clears.
    me = await store.updateProfile(claims, { avatar_url: "" });
    assertEquals(me.user?.display_name, "Pat Jones");
    assertEquals(me.user?.avatar_url, undefined);

    await assertRejects(
      () => store.updateProfile(claims, { display_name: "x".repeat(129) }),
      HubError,
      "display_name too long",
    );
    await assertRejects(
      () => store.updateProfile(claims, { avatar_url: "javascript:alert(1)" }),
      HubError,
      "avatar_url must be",
    );
    await assertRejects(
      () =>
        store.updateProfile(
          { sub: "auth0|stranger" },
          { display_name: "Ghost" },
        ),
      HubError,
      "Onboarding required",
    );
  });
});

Deno.test("update profile renames handle local part", async () => {
  await withTestStore(async ({ store }) => {
    const claims = { sub: "auth0|ren", email: "ren@co.test" };
    const { user } = await store.createOrgWithAdmin(claims, {
      slug: "renco",
      name: "RenCo",
      handle: "ren@renco",
    });

    let me = await store.updateProfile(claims, { handle: "rene" });
    assertEquals(me.user?.handle, "rene@renco");

    me = await store.updateProfile(claims, { handle: "pat@renco" });
    assertEquals(me.user?.handle, "pat@renco");

    // Old handle is free for someone else.
    const invite = await store.createInvite(store.authContextFromUser(user));
    const other = { sub: "auth0|other", email: "other@co.test" };
    await store.joinOrg(other, { invite_code: invite.code, handle: "ren@renco" });
    assertEquals((await store.getMe(other)).user?.handle, "ren@renco");

    await assertRejects(
      () => store.updateProfile(claims, { handle: "ren@renco" }),
      HubError,
      "Handle already registered",
    );
    await assertRejects(
      () => store.updateProfile(claims, { handle: "pat@otherorg" }),
      HubError,
      "Handle must stay in your org",
    );
    await assertRejects(
      () => store.updateProfile(claims, { handle: "" }),
      HubError,
      "handle is required",
    );
  });
});

Deno.test("update org slug rewrites member handles", async () => {
  await withTestStore(async ({ store, kv }) => {
    const adminClaims = { sub: "auth0|slugfix", email: "admin@typo.test" };
    const { user: admin } = await store.createOrgWithAdmin(adminClaims, {
      slug: "typo",
      name: "Typo Co",
      handle: "admin@typo",
    });
    const invite = await store.createInvite(store.authContextFromUser(admin));
    const memberClaims = { sub: "auth0|slugmem", email: "mem@typo.test" };
    await store.joinOrg(memberClaims, {
      invite_code: invite.code,
      handle: "mem@typo",
    });

    const me = await store.updateOrgSlug(store.authContextFromUser(admin), {
      slug: "fixed",
    });
    assertEquals(me.org?.slug, "fixed");
    assertEquals(me.user?.handle, "admin@fixed");
    assertEquals((await store.getMe(memberClaims)).user?.handle, "mem@fixed");

    // Old slug index gone; new slug resolves.
    assertEquals((await kv.get(["org_slugs", "typo"])).value, null);
    assertExists((await kv.get(["org_slugs", "fixed"])).value);
    assertEquals((await kv.get(["handles", "admin@typo"])).value, null);
    assertEquals((await kv.get(["handles", "admin@fixed"])).value, admin.id);

    // No-op same slug.
    const adminAfter = (await store.getMe(adminClaims)).user!;
    const memberAfter = (await store.getMe(memberClaims)).user!;
    const again = await store.updateOrgSlug(store.authContextFromUser(adminAfter), {
      slug: "fixed",
    });
    assertEquals(again.org?.slug, "fixed");

    await assertRejects(
      () => store.updateOrgSlug(store.authContextFromUser(memberAfter), { slug: "other" }),
      HubError,
      "Org admin required",
    );
    await assertRejects(
      () => store.updateOrgSlug(store.authContextFromUser(adminAfter), { slug: "BAD_SLUG" }),
      HubError,
      "Org slug must be lowercase alphanumeric",
    );

    await store.createOrgWithAdmin(
      { sub: "auth0|takenorg", email: "t@taken.test" },
      { slug: "taken", name: "Taken" },
    );
    await assertRejects(
      () => store.updateOrgSlug(store.authContextFromUser(adminAfter), { slug: "taken" }),
      HubError,
      "already exists",
    );

    await kv.set(["reserved_org_slugs", "openai"], {
      slug: "openai",
      listing_id: "listing-1",
      reserved_at: new Date().toISOString(),
      org_id: "ent-org",
    });
    await assertRejects(
      () => store.updateOrgSlug(store.authContextFromUser(adminAfter), { slug: "openai" }),
      HubError,
      "reserved for a verified enterprise",
    );
  });
});

Deno.test("Auth0 profile seed fills empty fields once", async () => {
  await withTestStore(async ({ store }) => {
    const claims = {
      sub: "auth0|seed",
      email: "seed@co.test",
      name: "Seed User",
      picture: "https://cdn.example.test/seed.jpg",
    };
    const { user } = await store.createOrgWithAdmin(claims, {
      slug: "seedco",
      name: "SeedCo",
    });
    assertEquals(user.display_name, "Seed User");
    assertEquals(user.avatar_url, "https://cdn.example.test/seed.jpg");
    assertEquals(user.email, "seed@co.test");
    assertEquals(typeof user.auth0_profile_seeded_at, "string");

    // Later Auth0 changes must not overwrite mutande profile.
    let me = await store.seedProfile(
      { ...claims, name: "Auth0 Renamed", picture: "https://cdn.example.test/new.jpg" },
      {
        display_name: "Auth0 Renamed",
        avatar_url: "https://cdn.example.test/new.jpg",
      },
    );
    assertEquals(me.user?.display_name, "Seed User");
    assertEquals(me.user?.avatar_url, "https://cdn.example.test/seed.jpg");

    // Clears stay cleared — seed does not refill name/photo.
    me = await store.updateProfile(claims, { display_name: "", avatar_url: "" });
    assertEquals(me.user?.display_name, undefined);
    assertEquals(me.user?.avatar_url, undefined);
    me = await store.seedProfile(claims, {
      display_name: "Back from Auth0",
      avatar_url: "https://cdn.example.test/again.jpg",
    });
    assertEquals(me.user?.display_name, undefined);
    assertEquals(me.user?.avatar_url, undefined);

    // Email can still backfill when missing.
    const bare = { sub: "auth0|emailonly" };
    await store.createOrgWithAdmin(bare, { slug: "emco", name: "EmCo", handle: "e@emco" });
    me = await store.getMe(bare);
    assertEquals(me.email, undefined);
    me = await store.seedProfile(bare, { email: "e@co.test" });
    assertEquals(me.email, "e@co.test");
    assertEquals(me.user?.email, "e@co.test");
  });
});

Deno.test("seedProfile from web session before flag is set", async () => {
  await withTestStore(async ({ store }) => {
    // Create without profile claims (typical access-token create).
    const claims = { sub: "auth0|late", email: "late@co.test" };
    const { user } = await store.createOrgWithAdmin(claims, {
      slug: "lateco",
      name: "LateCo",
    });
    assertEquals(user.auth0_profile_seeded_at, undefined);
    assertEquals(user.display_name, undefined);

    const me = await store.seedProfile(claims, {
      display_name: "Late Seed",
      avatar_url: "https://cdn.example.test/late.jpg",
      email: "late@co.test",
    });
    assertEquals(me.user?.display_name, "Late Seed");
    assertEquals(me.user?.avatar_url, "https://cdn.example.test/late.jpg");
    assertEquals(typeof me.user?.auth0_profile_seeded_at, "string");
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

Deno.test("contacts include display_name and avatar_url", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    await store.updateProfile(
      { sub: "auth0|bob", email: "bob@example.com" },
      {
        avatar_url: "https://cdn.example.test/bob.jpg",
        display_name: "Bob Builder",
      },
    );
    const bob = (await store.listContacts(aliceAuth)).contacts.find((c) => c.handle === "bob@acme");
    assertEquals(bob?.avatar_url, "https://cdn.example.test/bob.jpg");
    assertEquals(bob?.display_name, "Bob Builder");
    const alice = (await store.listContacts(bobAuth)).contacts.find((c) => c.handle === "alice@acme");
    assertEquals(alice?.avatar_url, undefined);
    assertEquals(alice?.display_name, undefined);
  });
});

Deno.test("registerDevice is idempotent by pubkey", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    const before = (await store.listDevices(aliceAuth)).devices.length;
    const first = await store.registerDevice(aliceAuth, {
      pubkey: "alice-reopen-pk",
      platform: "macos",
    });
    const second = await store.registerDevice(aliceAuth, {
      pubkey: "alice-reopen-pk",
      platform: "macos",
    });
    assertEquals(second.id, first.id);
    assertEquals((await store.listDevices(aliceAuth)).devices.length, before + 1);

    const ios = await store.registerDevice(aliceAuth, {
      pubkey: "alice-reopen-pk",
      platform: "ios",
    });
    assertEquals(ios.id, first.id);
    assertEquals(ios.platform, "ios");
    assertEquals((await store.listDevices(aliceAuth)).devices.length, before + 1);
  });
});

Deno.test("listDevices and contacts collapse legacy duplicate pubkeys", async () => {
  await withTestStore(async ({ store, kv }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    const alice = (await store.getMe({ sub: "auth0|alice", email: "alice@example.com" })).user!;
    const pubkey = "alice-legacy-dup-pk";
    const ids = ["dup-a", "dup-b", "dup-c"];
    for (let i = 0; i < ids.length; i++) {
      const id = ids[i]!;
      const device = {
        id,
        user_id: alice.id,
        pubkey,
        platform: "macos" as const,
        created_at: `2026-07-28T15:0${i}:00.000Z`,
      };
      await kv.set(["devices", id], device);
      await kv.set(["user_devices", alice.id, id], id);
    }

    const listed = await store.listDevices(aliceAuth);
    assertEquals(listed.devices.filter((d) => d.pubkey === pubkey).length, 1);
    assertEquals(listed.devices.find((d) => d.pubkey === pubkey)?.id, "dup-a");

    const contact = (await store.listContacts(bobAuth)).contacts.find((c) =>
      c.handle === "alice@acme"
    );
    assertEquals(contact?.devices.filter((d) => d.pubkey === pubkey).length, 1);

    // Re-register purges the extra KV rows.
    await store.registerDevice(aliceAuth, { pubkey, platform: "macos" });
    const rawLeft: string[] = [];
    for await (
      const entry of kv.list<string>({ prefix: ["user_devices", alice.id] })
    ) {
      const d = await kv.get<{ id: string; pubkey: string }>(["devices", entry.value]);
      if (d.value?.pubkey === pubkey) rawLeft.push(d.value.id);
    }
    assertEquals(rawLeft.length, 1);
    assertEquals(rawLeft[0], "dup-a");
  });
});

Deno.test("registerDevice concurrent-style races resolve to one device", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    const before = (await store.listDevices(aliceAuth)).devices.length;
    const results = await Promise.all(
      Array.from({ length: 8 }, () =>
        store.registerDevice(aliceAuth, {
          pubkey: "alice-race-pk",
          platform: "macos",
        })
      ),
    );
    const ids = new Set(results.map((d) => d.id));
    assertEquals(ids.size, 1);
    assertEquals((await store.listDevices(aliceAuth)).devices.length, before + 1);
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

Deno.test("OP can reply with correction and bumps recipient Needs you", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    const { thread } = await store.createThread(aliceAuth, {
      to: "bob@acme",
      envelope: sampleEnvelope("op"),
    });
    assertEquals((await store.listThreads(bobAuth, "needs_action")).threads.length, 1);

    // OP correction before anyone replies.
    await store.postReply(aliceAuth, thread.id, {
      envelope: sampleEnvelope("op-correction"),
    });
    assertEquals((await store.getThread(aliceAuth, thread.id)).messages.length, 2);
    assertEquals((await store.listThreads(bobAuth, "needs_action")).threads.length, 1);
    assertEquals((await store.listThreads(aliceAuth, "needs_action")).threads.length, 0);

    // Bob replies, then OP corrects again — bob Needs you again.
    await store.postReply(bobAuth, thread.id, { envelope: sampleEnvelope("bob-r") });
    assertEquals((await store.listThreads(bobAuth, "needs_action")).threads.length, 0);
    assertEquals((await store.listThreads(aliceAuth, "needs_action")).threads.length, 1);
    await store.postReply(aliceAuth, thread.id, {
      envelope: sampleEnvelope("op-again"),
    });
    assertEquals((await store.getThread(aliceAuth, thread.id)).messages.length, 4);
    assertEquals((await store.listThreads(bobAuth, "needs_action")).threads.length, 1);
    assertEquals((await store.listThreads(aliceAuth, "needs_action")).threads.length, 0);
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

Deno.test("bare @all is one shared my-agents group thread", async () => {
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

    // Peer agents see each other's replies (unlike org @all@org).
    await store.postReply(aliceAuth, thread.id, {
      envelope: sampleEnvelope("claude-reply"),
      from_agent: "claude",
    });
    const { messages } = await store.getThread(aliceAuth, thread.id);
    assertEquals(messages.length, 2);
    assertEquals(messages[1]!.from_handle.endsWith("/claude"), true);
    assertEquals(messages[1]!.sender_only, false);
  });
});

Deno.test("@all@org replies stay sender-only for other members", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth, carolAuth } = await setupOrgWithUsers(store);
    const { thread } = await store.createThread(aliceAuth, {
      to: "@all@acme",
      envelope: sampleEnvelope("org-ann"),
      from_agent: "cursor",
    });
    await store.postReply(bobAuth, thread.id, {
      envelope: sampleEnvelope("bob-reply"),
      from_agent: "claude",
    });
    const bobView = await store.getThread(bobAuth, thread.id);
    assertEquals(bobView.messages.length, 2);
    const carolView = await store.getThread(carolAuth, thread.id);
    // Carol sees root + not bob's sender_only reply.
    assertEquals(carolView.messages.length, 1);
    assertEquals(carolView.messages[0]!.from_user_id, aliceAuth.userId);
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

Deno.test("L1 dual agent rows same slug different transport", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    const sidecar = await store.connectAgent(aliceAuth, "sidecar", {
      slug: "chatgpt",
      models: ["local"],
    });
    const mcp = await store.connectAgent(aliceAuth, "mcp", {
      slug: "chatgpt",
      models: ["gpt-4o"],
      default_model: "gpt-4o",
      modalities: ["text", "image"],
      message_types: ["thread", "question"],
    });
    assertEquals(sidecar.slug, "chatgpt");
    assertEquals(mcp.slug, "chatgpt");
    assertEquals(sidecar.transport, "sidecar");
    assertEquals(mcp.transport, "mcp");
    assertEquals(sidecar.id === mcp.id, false);
    assertEquals(mcp.mcp_endpoint, "https://mcp.mutande.online");
    assertEquals(sidecar.mcp_endpoint, null);
    assertEquals(mcp.visibility, "private");
    assertEquals(mcp.trust_tier, "org");
    assertEquals(mcp.billing, null);

    const { agents } = await store.listAgents(aliceAuth);
    const chatgptRows = agents.filter((a) => a.slug === "chatgpt");
    assertEquals(chatgptRows.length, 2);
    assertEquals(new Set(chatgptRows.map((a) => a.transport)).size, 2);
  });
});

Deno.test("L1 client cannot elevate trust_tier or transport", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    const agent = await store.connectAgent(aliceAuth, "sidecar", {
      slug: "research",
      models: ["x"],
      trust_tier: "enterprise",
      visibility: "public",
      billing: { methods: ["per_message"], price_usd: "1", currency: "USD" },
      transport: "mcp",
      agent_id: "00000000-0000-0000-0000-000000000099",
    });
    assertEquals(agent.transport, "sidecar");
    assertEquals(agent.trust_tier, "org");
    assertEquals(agent.visibility, "private");
    assertEquals(agent.billing, null);
    assertEquals(agent.id === "00000000-0000-0000-0000-000000000099", false);
    assertEquals(agent.capabilities?.models, ["x"]);
  });
});

Deno.test("L1 stale capability does not block resolve", async () => {
  await withTestStore(async ({ store, kv }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    const mcp = await store.connectAgent(aliceAuth, "mcp", {
      slug: "webslot",
      models: ["gpt-4o"],
    });
    await store.setTransportDefault(aliceAuth, { slug: "webslot", transport: "mcp" });

    const staleAt = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    await kv.set(["agents", mcp.id], {
      ...mcp,
      capabilities_updated_at: staleAt,
    });
    const stored = (await kv.get<typeof mcp>(["agents", mcp.id])).value!;
    assertEquals(agentCapabilitiesFresh(stored as typeof mcp), false);

    // Staleness is UI-only — routing still resolves the slot.
    const { thread } = await store.createThread(bobAuth, {
      to: "alice@acme/webslot",
      app_envelope: { version: 1, notes: "stale-ok" },
      from_agent: "claude",
    });
    assertEquals(thread.audience_agent_id, mcp.id);
    assertEquals(thread.audience, "alice@acme/webslot");
    assertEquals(thread.encryption_mode, "app_envelope");
  });
});

Deno.test("L1 transport default prefers configured slot", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    const sidecar = await store.connectAgent(aliceAuth, "sidecar", { slug: "dual" });
    const mcp = await store.connectAgent(aliceAuth, "mcp", { slug: "dual" });
    // Dual slots share an identity — sibling mcp forces app_envelope even when
    // the preferred audience row is still sidecar.
    const { thread: t1 } = await store.createThread(bobAuth, {
      to: "alice@acme/dual",
      app_envelope: { version: 1, notes: "both-slots" },
      from_agent: "claude",
    });
    assertEquals(t1.audience_agent_id, sidecar.id);
    assertEquals(t1.encryption_mode, "app_envelope");

    await store.setTransportDefault(aliceAuth, { slug: "dual", transport: "mcp" });
    const prefs = await store.getTransportPrefs(aliceAuth);
    assertEquals(prefs.defaults["dual"], "mcp");

    const { thread: t2 } = await store.createThread(bobAuth, {
      to: "alice@acme/dual",
      app_envelope: { version: 1, notes: "pref-mcp" },
      from_agent: "claude",
    });
    assertEquals(t2.audience_agent_id, mcp.id);
    assertEquals(t2.encryption_mode, "app_envelope");
  });
});
