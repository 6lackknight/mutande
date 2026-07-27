import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { HubError } from "./errors.ts";
import { HubStore, createStore } from "./store.ts";
import type { Envelope } from "./types.ts";
import { MAX_ENVELOPE_BYTES, ORG_BLOB_QUOTA_BYTES } from "./types.ts";

const JWT_SECRET = "test-secret";

function sampleEnvelope(tag = "a"): Envelope {
  return {
    version: 1,
    content_nonce: Array(12).fill(0),
    ciphertext: Array.from(new TextEncoder().encode(`cipher-${tag}`)),
    wraps: [{
      recipient: Array(32).fill(1),
      ephemeral_public: Array(32).fill(2),
      boxed_cek: [4, 5, 6],
    }],
  };
}

async function withStore(fn: (store: HubStore) => Promise<void>): Promise<void> {
  const kv = await Deno.openKv(":memory:");
  const store = new HubStore(kv, JWT_SECRET);
  try {
    await fn(store);
  } finally {
    kv.close();
  }
}

async function setupOrgWithUsers(store: HubStore) {
  const org = await store.createOrg("acme");
  const invite1 = await store.createInvite(org.id);
  const invite2 = await store.createInvite(org.id);
  const invite3 = await store.createInvite(org.id);

  const aliceReg = await store.register({
    invite_code: invite1.code,
    handle: "alice@acme",
    pubkey: "alice-pk",
  });
  const bobReg = await store.register({
    invite_code: invite2.code,
    handle: "bob@acme",
    pubkey: "bob-pk",
  });
  const carolReg = await store.register({
    invite_code: invite3.code,
    handle: "carol@acme",
    pubkey: "carol-pk",
  });

  return {
    org,
    alice: aliceReg.user,
    bob: bobReg.user,
    carol: carolReg.user,
    aliceAuth: { userId: aliceReg.user.id, orgId: org.id, handle: "alice@acme" },
    bobAuth: { userId: bobReg.user.id, orgId: org.id, handle: "bob@acme" },
    carolAuth: { userId: carolReg.user.id, orgId: org.id, handle: "carol@acme" },
  };
}

Deno.test("register user and auth JWT", async () => {
  await withStore(async (store) => {
    const org = await store.createOrg("acme");
    const invite = await store.createInvite(org.id);

    const reg = await store.register({
      invite_code: invite.code,
      handle: "alice@acme",
      pubkey: "alice-pk",
    });
    assertEquals(reg.user.handle, "alice@acme");
    assertEquals(reg.access_token.split(".").length, 3);

    const auth = await store.verifyAccessToken(reg.access_token);
    assertEquals(auth.userId, reg.user.id);
    assertEquals(auth.handle, "alice@acme");

    const refreshed = await store.refreshToken(reg.refresh_token);
    const auth2 = await store.verifyAccessToken(refreshed.access_token);
    assertEquals(auth2.userId, reg.user.id);
  });
});

Deno.test("list contacts includes @all@org", async () => {
  await withStore(async (store) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);

    const aliceContacts = await store.listContacts(aliceAuth);
    const aliceHandles = aliceContacts.contacts.map((c) => c.handle);
    assertEquals(aliceHandles.includes("@all@acme"), true);
    assertEquals(aliceHandles.includes("bob@acme"), true);
    assertEquals(aliceHandles.includes("alice@acme"), false);
    assertEquals(
      aliceContacts.contacts.find((c) => c.handle === "bob@acme")?.pubkey,
      "bob-pk",
    );
    assertEquals(
      aliceContacts.contacts.find((c) => c.handle === "@all@acme")?.pubkey,
      null,
    );

    const bobContacts = await store.listContacts(bobAuth);
    assertEquals(
      bobContacts.contacts.some((c) => c.handle === "alice@acme"),
      true,
    );
    assertEquals(
      bobContacts.contacts.find((c) => c.handle === "alice@acme")?.pubkey,
      "alice-pk",
    );
  });
});

Deno.test("create direct thread and inbox filters", async () => {
  await withStore(async (store) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);

    const { thread } = await store.createThread(aliceAuth, {
      to: "bob@acme",
      envelope: sampleEnvelope("handoff"),
    });
    assertEquals(thread.kind, "direct");
    assertEquals(thread.status, "open");

    const bobNeeds = await store.listThreads(bobAuth, "needs_action");
    assertEquals(bobNeeds.threads.length, 1);
    assertEquals(bobNeeds.threads[0].your_status, "pending");

    const aliceOpen = await store.listThreads(aliceAuth, "open");
    assertEquals(aliceOpen.threads.length, 1);
    assertEquals(aliceOpen.threads[0].your_status, "replied");

    await store.postReply(bobAuth, thread.id, { envelope: sampleEnvelope("reply") });

    const bobAfter = await store.listThreads(bobAuth, "needs_action");
    assertEquals(bobAfter.threads.length, 0);

    await store.closeThread(aliceAuth, thread.id);
    const closed = await store.listThreads(aliceAuth, "closed");
    assertEquals(closed.threads.length, 1);
  });
});

Deno.test("broadcast fan-out creates inbox per member", async () => {
  await withStore(async (store) => {
    const { aliceAuth, bobAuth, carolAuth } = await setupOrgWithUsers(store);

    const { thread } = await store.createThread(aliceAuth, {
      to: "@all@acme",
      envelope: sampleEnvelope("broadcast"),
    });
    assertEquals(thread.kind, "broadcast");
    assertEquals(thread.participant_count, 3);

    for (const auth of [bobAuth, carolAuth]) {
      const inbox = await store.listThreads(auth, "needs_action");
      assertEquals(inbox.threads.length, 1);
    }

    await store.postReply(bobAuth, thread.id, { envelope: sampleEnvelope("bob-reply") });
    await store.postReply(carolAuth, thread.id, { envelope: sampleEnvelope("carol-reply") });

    const senderView = await store.getThread(aliceAuth, thread.id);
    assertEquals(senderView.messages.length, 3);

    const bobView = await store.getThread(bobAuth, thread.id);
    assertEquals(bobView.messages.length, 2);
    assertEquals(bobView.messages.every((m) => m.from_handle !== "carol@acme"), true);
  });
});

Deno.test("draft CRUD and delete", async () => {
  await withStore(async (store) => {
    const { aliceAuth } = await setupOrgWithUsers(store);

    const draft = await store.createDraft(aliceAuth, sampleEnvelope("draft"));
    const listed = await store.listDrafts(aliceAuth);
    assertEquals(listed.drafts.length, 1);

    await store.updateDraft(aliceAuth, draft.id, sampleEnvelope("draft-v2"));
    const fetched = await store.getDraft(aliceAuth, draft.id);
    assertEquals(
      fetched.envelope.ciphertext,
      Array.from(new TextEncoder().encode("cipher-draft-v2")),
    );

    await store.deleteDraft(aliceAuth, draft.id);
    assertEquals((await store.listDrafts(aliceAuth)).drafts.length, 0);
  });
});

Deno.test("org scoping rejects cross-org recipient", async () => {
  await withStore(async (store) => {
    const { aliceAuth } = await setupOrgWithUsers(store);

    const otherOrg = await store.createOrg("rival");
    const invite = await store.createInvite(otherOrg.id);
    await store.register({
      invite_code: invite.code,
      handle: "eve@rival",
      pubkey: "eve-pk",
    });

    await assertRejects(
      () => store.createThread(aliceAuth, { to: "eve@rival", envelope: sampleEnvelope() }),
    );
  });
});

Deno.test("rejects oversized envelope", async () => {
  await withStore(async (store) => {
    const { aliceAuth } = await setupOrgWithUsers(store);

    const huge: Envelope = {
      version: 1,
      content_nonce: Array(12).fill(0),
      ciphertext: Array(MAX_ENVELOPE_BYTES).fill(120),
      wraps: [],
    };

    await assertRejects(
      () => store.createThread(aliceAuth, { to: "bob@acme", envelope: huge }),
    );
  });
});

Deno.test("blob upload-url tracks org quota", async () => {
  await withStore(async (store) => {
    const { aliceAuth } = await setupOrgWithUsers(store);

    const small = await store.createUploadUrl(aliceAuth, 1024);
    assertEquals(small.upload_url.startsWith("https://blobs.mutande.app/"), true);

    const dl = await store.createDownloadUrl(aliceAuth, small.blob_id);
    assertEquals(dl.download_url.includes(small.blob_id), true);

    await assertRejects(
      () => store.createUploadUrl(aliceAuth, ORG_BLOB_QUOTA_BYTES),
    );
  });
});

Deno.test("register rejects @all broadcast handle", async () => {
  await withStore(async (store) => {
    const org = await store.createOrg("acme");
    const invite = await store.createInvite(org.id);

    await assertRejects(
      () =>
        store.register({
          invite_code: invite.code,
          handle: "@all@acme",
          pubkey: "bad-pk",
        }),
    );
  });
});

Deno.test("register rejects @ALL@ broadcast handle case-insensitively", async () => {
  await withStore(async (store) => {
    const org = await store.createOrg("acme");
    const invite = await store.createInvite(org.id);

    await assertRejects(
      () =>
        store.register({
          invite_code: invite.code,
          handle: "@ALL@acme",
          pubkey: "bad-pk",
        }),
      HubError,
      "Handle cannot use @all broadcast prefix",
    );
  });
});

Deno.test("register concurrent same invite yields one winner", async () => {
  await withStore(async (store) => {
    const org = await store.createOrg("race");
    const invite = await store.createInvite(org.id);

    const results = await Promise.allSettled([
      store.register({
        invite_code: invite.code,
        handle: "a@race",
        pubkey: "a-pk",
      }),
      store.register({
        invite_code: invite.code,
        handle: "b@race",
        pubkey: "b-pk",
      }),
    ]);

    const fulfilled = results.filter((r) => r.status === "fulfilled");
    const rejected = results.filter((r) => r.status === "rejected");
    assertEquals(fulfilled.length, 1);
    assertEquals(rejected.length, 1);
    const err = (rejected[0] as PromiseRejectedResult).reason;
    assertEquals(err instanceof HubError, true);
    assertEquals((err as HubError).status, 409);
  });
});

Deno.test("createStore hard-fails without JWT_SECRET on deploy", async () => {
  const kv = await Deno.openKv(":memory:");
  const prevDeploy = Deno.env.get("DENO_DEPLOYMENT_ID");
  const prevJwt = Deno.env.get("JWT_SECRET");
  Deno.env.set("DENO_DEPLOYMENT_ID", "test-deploy");
  Deno.env.delete("JWT_SECRET");
  try {
    assertThrows(
      () => createStore(kv),
      Error,
      "JWT_SECRET must be set in production",
    );
  } finally {
    if (prevDeploy === undefined) Deno.env.delete("DENO_DEPLOYMENT_ID");
    else Deno.env.set("DENO_DEPLOYMENT_ID", prevDeploy);
    if (prevJwt === undefined) Deno.env.delete("JWT_SECRET");
    else Deno.env.set("JWT_SECRET", prevJwt);
    kv.close();
  }
});

Deno.test("org invite accept on register", async () => {
  await withStore(async (store) => {
    const org = await store.createOrg("startup");
    const invite = await store.createInvite(org.id);

    const reg = await store.register({
      invite_code: invite.code,
      handle: "founder@startup",
      pubkey: "fpk",
    });
    assertEquals(reg.user.org_id, org.id);

    await assertRejects(
      () =>
        store.register({
          invite_code: invite.code,
          handle: "other@startup",
          pubkey: "opk",
        }),
    );
  });
});
