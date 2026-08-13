/**
 * L3 external contacts — PIN flow, rate limits, uniform errors, unpair.
 */
import {
  assertEquals,
  assertExists,
  assertRejects,
} from "jsr:@std/assert@1";
import { HubError } from "./errors.ts";
import { createStoreWithTestAuth, type HubStore } from "./store.ts";
import type { Auth0Claims, AuthContext } from "./types.ts";
import {
  PAIRING_FAILED_MESSAGE,
  PAIRING_RATE_LIMIT_MESSAGE,
  PAIR_WRONG_PIN_LIMIT,
  pairFailureKey,
  type PairFailureState,
} from "./external_pairing.ts";

async function withTestStore(
  fn: (ctx: {
    store: HubStore;
    kv: Deno.Kv;
  }) => Promise<void>,
) {
  const kv = await Deno.openKv(":memory:");
  const { store } = await createStoreWithTestAuth(kv);
  try {
    await fn({ store, kv });
  } finally {
    kv.close();
  }
}

async function twoOrgs(store: HubStore) {
  const { user: alice } = await store.createOrgWithAdmin(
    { sub: "auth0|alice", email: "alice@aliceco.test" } as Auth0Claims,
    { slug: "aliceco", name: "Alice Co", handle: "alice@aliceco" },
  );
  const { user: bob } = await store.createOrgWithAdmin(
    { sub: "auth0|bob", email: "bob@acme.test" } as Auth0Claims,
    { slug: "acme", name: "Acme", handle: "bob@acme" },
  );
  await store.registerAgent(store.authContextFromUser(alice), { slug: "cursor" });
  await store.registerAgent(store.authContextFromUser(bob), { slug: "claude" });
  await store.registerDevice(store.authContextFromUser(alice), {
    pubkey: "alice-pk",
    platform: "macos",
  });
  await store.registerDevice(store.authContextFromUser(bob), {
    pubkey: "bob-pk",
    platform: "macos",
  });
  return {
    aliceAuth: store.authContextFromUser(alice),
    bobAuth: store.authContextFromUser(bob),
    alice,
    bob,
  };
}

Deno.test("pairing PIN issue + QR URI", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await twoOrgs(store);
    const pin = await store.issuePairingPin(aliceAuth);
    assertEquals(pin.handle, "alice@aliceco");
    assertEquals(pin.pin.length, 6);
    assertEquals(/^\d{6}$/.test(pin.pin), true);
    assertEquals(
      pin.qr_uri,
      `mutande://pair?handle=alice%40aliceco&pin=${pin.pin}`,
    );
    const got = await store.getPairingPin(aliceAuth);
    assertEquals(got?.pin, pin.pin);
  });
});

Deno.test("pairing PIN rotate invalidates previous", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await twoOrgs(store);
    const first = await store.issuePairingPin(aliceAuth);
    const second = await store.rotatePairingPin(aliceAuth);
    assertEquals(first.pin === second.pin, false);

    await assertRejects(
      () =>
        store.submitPairRequest(bobAuth, {
          handle: "alice@aliceco",
          pin: first.pin,
        }),
      HubError,
      PAIRING_FAILED_MESSAGE,
    );

    const ok = await store.submitPairRequest(bobAuth, {
      handle: "alice@aliceco",
      pin: second.pin,
      intro: "hi from bob",
    });
    assertEquals(ok.request.status, "pending");
    assertEquals(ok.request.intro, "hi from bob");
  });
});

Deno.test("uniform error for unknown handle and wrong PIN", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await twoOrgs(store);
    await store.issuePairingPin(aliceAuth);

    const unknown = await assertRejects(
      () =>
        store.submitPairRequest(bobAuth, {
          handle: "nobody@nowhere",
          pin: "123456",
        }),
      HubError,
    ) as HubError;
    assertEquals(unknown.message, PAIRING_FAILED_MESSAGE);
    assertEquals(unknown.code, "pairing_failed");

    const wrong = await assertRejects(
      () =>
        store.submitPairRequest(bobAuth, {
          handle: "alice@aliceco",
          pin: "000000",
        }),
      HubError,
    ) as HubError;
    assertEquals(wrong.message, PAIRING_FAILED_MESSAGE);
    assertEquals(wrong.code, "pairing_failed");
  });
});

Deno.test("5 wrong PINs lock pair for 1h", async () => {
  await withTestStore(async ({ store, kv }) => {
    const { aliceAuth, bobAuth } = await twoOrgs(store);
    await store.issuePairingPin(aliceAuth);

    for (let i = 0; i < PAIR_WRONG_PIN_LIMIT; i++) {
      await assertRejects(
        () =>
          store.submitPairRequest(bobAuth, {
            handle: "alice@aliceco",
            pin: "999999",
          }),
        HubError,
      );
    }

    const fail = await kv.get<PairFailureState>(
      pairFailureKey(bobAuth.userId, "alice@aliceco"),
    );
    assertExists(fail.value?.locked_until);

    const locked = await assertRejects(
      () =>
        store.submitPairRequest(bobAuth, {
          handle: "alice@aliceco",
          pin: "999999",
        }),
      HubError,
    ) as HubError;
    assertEquals(locked.message, PAIRING_RATE_LIMIT_MESSAGE);
    assertEquals(locked.code, "pairing_rate_limited");
  });
});

Deno.test("approve creates bilateral contact + connection ping", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await twoOrgs(store);
    const pin = await store.issuePairingPin(aliceAuth);
    const { request } = await store.submitPairRequest(bobAuth, {
      handle: "alice@aliceco",
      pin: pin.pin,
      intro: "Ready to collab",
    });

    const approved = await store.approvePairRequest(aliceAuth, request.id);
    assertEquals(approved.contact.handle, "bob@acme");
    assertEquals(approved.contact.kind, "external");
    assertEquals(approved.thread.encryption_mode, "app_envelope");
    assertExists(approved.thread.external_link_id);

    await store.updateProfile(
      { sub: "auth0|bob", email: "bob@acme.test" } as Auth0Claims,
      { avatar_url: "https://cdn.example.test/bob.jpg" },
    );
    const aliceExt = await store.listExternalContacts(aliceAuth);
    const bobExt = await store.listExternalContacts(bobAuth);
    assertEquals(aliceExt.contacts.length, 1);
    assertEquals(bobExt.contacts.length, 1);
    assertEquals(aliceExt.contacts[0]!.handle, "bob@acme");
    assertEquals(aliceExt.contacts[0]!.avatar_url, "https://cdn.example.test/bob.jpg");
    assertEquals(bobExt.contacts[0]!.handle, "alice@aliceco");

    // Both see the connection ping thread.
    const aliceThreads = await store.listThreads(aliceAuth);
    const bobThreads = await store.listThreads(bobAuth);
    assertEquals(
      aliceThreads.threads.some((t) => t.id === approved.thread.id),
      true,
    );
    assertEquals(
      bobThreads.threads.some((t) => t.id === approved.thread.id),
      true,
    );

    const detail = await store.getThread(bobAuth, approved.thread.id);
    assertEquals(detail.messages.length >= 1, true);
    assertEquals(detail.thread.encryption_mode, "app_envelope");
  });
});

Deno.test("deny blocks requester; unpair closes threads", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await twoOrgs(store);
    const pin = await store.issuePairingPin(aliceAuth);
    const { request } = await store.submitPairRequest(bobAuth, {
      handle: "alice@aliceco",
      pin: pin.pin,
    });
    await store.denyPairRequest(aliceAuth, request.id);

    // Blocked — uniform failure even with correct new PIN.
    const pin2 = await store.rotatePairingPin(aliceAuth);
    await assertRejects(
      () =>
        store.submitPairRequest(bobAuth, {
          handle: "alice@aliceco",
          pin: pin2.pin,
        }),
      HubError,
      PAIRING_FAILED_MESSAGE,
    );
  });
});

Deno.test("approve then unpair closes shared threads read-only", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await twoOrgs(store);
    const pin = await store.issuePairingPin(aliceAuth);
    const { request } = await store.submitPairRequest(bobAuth, {
      handle: "alice@aliceco",
      pin: pin.pin,
    });
    const approved = await store.approvePairRequest(aliceAuth, request.id);
    const linkId = approved.contact.external_link_id!;

    // Cross-org mail allowed while linked.
    const sent = await store.createThread(bobAuth, {
      to: "alice@aliceco",
      app_envelope: { version: 1, notes: "hello external" },
    });
    assertEquals(sent.thread.encryption_mode, "app_envelope");
    assertEquals(sent.thread.external_link_id, linkId);

    const unpair = await store.unpairExternalContact(aliceAuth, linkId);
    assertEquals(unpair.ok, true);
    assertEquals(unpair.closed_thread_ids.includes(approved.thread.id), true);

    const aliceExt = await store.listExternalContacts(aliceAuth);
    assertEquals(aliceExt.contacts.length, 0);

    // Closed — cannot reply.
    await assertRejects(
      () =>
        store.postReply(bobAuth, approved.thread.id, {
          app_envelope: { version: 1, notes: "after unpair" },
        }),
      HubError,
    );

    // New cross-org mail denied without link.
    await assertRejects(
      () =>
        store.createThread(bobAuth, {
          to: "alice@aliceco",
          app_envelope: { version: 1, notes: "nope" },
        }),
      HubError,
    );
  });
});

Deno.test("ops flag after 5 denies from different users in 7d", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, alice } = await twoOrgs(store);
    const pin = await store.issuePairingPin(aliceAuth);

    const requesters: AuthContext[] = [];
    for (let i = 0; i < 5; i++) {
      const { user } = await store.createOrgWithAdmin(
        { sub: `auth0|req${i}`, email: `r${i}@org${i}.test` } as Auth0Claims,
        { slug: `org${i}`, name: `Org ${i}`, handle: `r${i}@org${i}` },
      );
      await store.registerAgent(store.authContextFromUser(user), {
        slug: "cursor",
      });
      const auth = store.authContextFromUser(user);
      requesters.push(auth);
      // Fresh PIN each time (rotate) so each can submit.
      const p = i === 0 ? pin : await store.rotatePairingPin(aliceAuth);
      const { request } = await store.submitPairRequest(auth, {
        handle: alice.handle!,
        pin: p.pin,
      });
      await store.denyPairRequest(aliceAuth, request.id);
    }

    const flags = await store.listPairingOpsFlags({
      ...aliceAuth,
      auth0Roles: ["SuperAdmin"],
    });
    assertEquals(flags.flags.length >= 1, true);
    assertEquals(flags.flags[0]!.type, "pairing_harassment");
    assertEquals(flags.flags[0]!.target_handle, "alice@aliceco");
    assertEquals(flags.flags[0]!.distinct_requesters.length, 5);
  });
});
