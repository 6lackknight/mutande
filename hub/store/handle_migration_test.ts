import { assertEquals, assertExists, assertRejects } from "jsr:@std/assert@1";
import { HubError } from "./errors.ts";
import { HubStore, createStoreWithTestAuth } from "./store.ts";
import {
  LOWERCASE_HANDLES_MIGRATION_KEY,
  migrateHandlesToLowercase,
  type HandleMigrationReport,
} from "./handle_migration.ts";
import type { Auth0Claims, ExternalContactLink, User } from "./types.ts";

async function withTestStore(
  fn: (ctx: { store: HubStore; kv: Deno.Kv }) => Promise<void>,
) {
  const kv = await Deno.openKv(":memory:");
  const { store } = await createStoreWithTestAuth(kv);
  try {
    await fn({ store, kv });
  } finally {
    kv.close();
  }
}

async function setupOrg(store: HubStore) {
  const { user: alice } = await store.createOrgWithAdmin(
    { sub: "auth0|alice", email: "alice@example.com" } as Auth0Claims,
    { slug: "acme", name: "Acme", handle: "alice@acme" },
  );
  const inv = await store.createInvite(store.authContextFromUser(alice));
  const { user: bob } = await store.joinOrg(
    { sub: "auth0|bob", email: "bob@example.com" } as Auth0Claims,
    { invite_code: inv.code, handle: "bob@acme" },
  );
  await store.registerAgent(store.authContextFromUser(bob), {
    slug: "claude",
  });
  return {
    aliceAuth: store.authContextFromUser(alice),
    bobAuth: store.authContextFromUser(bob),
    alice,
    bob,
  };
}

/** Rewrite bob's stored data to legacy mixed casing, bypassing store normalization. */
async function corruptBobCasing(kv: Deno.Kv, bob: User) {
  await kv.delete(["handles", "bob@acme"]);
  await kv.set(["handles", "Bob@acme"], bob.id);
  await kv.set(["users", bob.id], { ...bob, handle: "Bob@acme" });
}

Deno.test("migration rewrites mixed-case handle index keys and user records", async () => {
  await withTestStore(async ({ store, kv }) => {
    const { bob } = await setupOrg(store);
    await corruptBobCasing(kv, bob);

    const report = await migrateHandlesToLowercase(kv);
    assertExists(report);
    assertEquals(report!.handle_keys, 1);
    assertEquals(report!.users, 1);
    assertEquals(report!.conflicts, []);

    const moved = await kv.get<string>(["handles", "bob@acme"]);
    assertEquals(moved.value, bob.id);
    const stale = await kv.get<string>(["handles", "Bob@acme"]);
    assertEquals(stale.value, null);
    const user = await kv.get<User>(["users", bob.id]);
    assertEquals(user.value?.handle, "bob@acme");

    const marker = await kv.get<HandleMigrationReport>(
      LOWERCASE_HANDLES_MIGRATION_KEY,
    );
    assertEquals(marker.value?.handle_keys, 1);

    // Second run is a no-op behind the marker.
    assertEquals(await migrateHandlesToLowercase(kv), null);
  });
});

Deno.test("migration restores list_agents for legacy mixed-case handles", async () => {
  await withTestStore(async ({ store, kv }) => {
    const { aliceAuth, bob } = await setupOrg(store);
    await corruptBobCasing(kv, bob);

    // Legacy state: the lowercase lookup misses the mixed-case index key.
    await assertRejects(
      () => store.listAgentsForHandle(aliceAuth, "bob@acme"),
      HubError,
      "User",
    );

    await migrateHandlesToLowercase(kv);

    const lower = await store.listAgentsForHandle(aliceAuth, "bob@acme");
    assertEquals(lower.agents.map((a) => a.slug), ["claude"]);
    // Old clients that still send hub casing keep working too.
    const mixed = await store.listAgentsForHandle(aliceAuth, "Bob@acme");
    assertEquals(mixed.agents.map((a) => a.slug), ["claude"]);
  });
});

Deno.test("migration normalizes external link and pair request handle snapshots", async () => {
  await withTestStore(async ({ kv }) => {
    const link: ExternalContactLink = {
      id: "l1",
      user_a_id: "ua",
      user_a_handle: "Alice@acme",
      user_b_id: "ub",
      user_b_handle: "Carol@other",
      created_at: "2026-01-01T00:00:00Z",
      thread_id: "t1",
    };
    await kv.set(["external_contacts", link.id], link);
    await kv.set(["pair_requests", "r1"], {
      id: "r1",
      requester_user_id: "ua",
      requester_handle: "Alice@acme",
      target_user_id: "ub",
      target_handle: "Carol@other",
      status: "pending",
      created_at: "2026-01-01T00:00:00Z",
    });
    await kv.set(["pairing_pins", "ub"], {
      user_id: "ub",
      handle: "Carol@other",
      pin: "123456",
      created_at: "2026-01-01T00:00:00Z",
      expires_at: "2027-01-01T00:00:00Z",
    });

    const report = await migrateHandlesToLowercase(kv);
    assertEquals(report!.external_links, 1);
    assertEquals(report!.pair_requests, 1);
    assertEquals(report!.pairing_pins, 1);

    const migrated = await kv.get<ExternalContactLink>([
      "external_contacts",
      link.id,
    ]);
    assertEquals(migrated.value?.user_a_handle, "alice@acme");
    assertEquals(migrated.value?.user_b_handle, "carol@other");
  });
});

Deno.test("migration keeps both mappings on lowercase conflicts", async () => {
  await withTestStore(async ({ kv }) => {
    await kv.set(["handles", "alice@acme"], "user-1");
    await kv.set(["handles", "Alice@acme"], "user-2");

    const report = await migrateHandlesToLowercase(kv);
    assertEquals(report!.conflicts, ["Alice@acme"]);
    assertEquals(report!.handle_keys, 0);

    // Neither mapping deleted — conflict needs manual ops.
    assertEquals((await kv.get(["handles", "alice@acme"])).value, "user-1");
    assertEquals((await kv.get(["handles", "Alice@acme"])).value, "user-2");
  });
});

Deno.test("handle lookups are case-insensitive without migration", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrg(store);
    // Data at rest is lowercase; any client casing must resolve.
    const res = await store.listAgentsForHandle(aliceAuth, "BOB@ACME");
    assertEquals(res.agents.map((a) => a.slug), ["claude"]);
  });
});
