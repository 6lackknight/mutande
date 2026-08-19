import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { Hono } from "hono";
import { handleHubError } from "../middleware/auth.ts";
import { createAdminRoutes } from "../routes/admin.ts";
import { createOrgRoutes } from "../routes/orgs.ts";
import { HubError } from "./errors.ts";
import { createStoreWithTestAuth, type HubStore } from "./store.ts";
import type { AuthContext, Envelope } from "./types.ts";

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

function ops(auth: AuthContext): AuthContext {
  return { ...auth, auth0Roles: ["SuperAdmin"] };
}

async function withStore(
  fn: (store: HubStore) => Promise<void>,
) {
  const kv = await Deno.openKv(":memory:");
  const { store } = await createStoreWithTestAuth(kv);
  try {
    await fn(store);
  } finally {
    kv.close();
  }
}

Deno.test("ops census requires SuperAdmin", async () => {
  await withStore(async (store) => {
    const { user } = await store.createOrgWithAdmin(
      { sub: "auth0|solo", email: "solo@co.io" },
      { slug: "co" },
    );
    await assertRejects(
      () => store.listOpsCensus(store.authContextFromUser(user)),
      HubError,
      "Platform admin required",
    );
  });
});

Deno.test("solo org stays fresh-start; multi-host and replied threads count", async () => {
  await withStore(async (store) => {
    const { user } = await store.createOrgWithAdmin(
      { sub: "auth0|solo", email: "solo@co.io" },
      { slug: "solo", handle: "solo@solo" },
    );
    const auth = store.authContextFromUser(user);
    await store.registerDevice(auth, { pubkey: "pk", platform: "macos" });
    await store.registerAgent(auth, { slug: "cursor" });
    await store.registerAgent(auth, { slug: "claude" });
    const { thread } = await store.createThread(auth, {
      to: "@all",
      envelope: sampleEnvelope("op"),
      from_agent: "cursor",
    });
    await store.postReply(auth, thread.id, {
      envelope: sampleEnvelope("pong"),
      from_agent: "claude",
    });

    const census = await store.listOpsCensus(ops(auth));
    assertEquals(census.users, 1);
    assertEquals(census.orgs, 1);
    assertEquals(census.multi_host_users, 1);
    assertEquals(census.orgs_with_2plus_members, 0);
    assertEquals(census.replied_threads, 1);
    assertEquals(census.users_active_7d, 1);
    assertEquals(census.storage_status, "fresh_start_ok");
    assertEquals(census.targets.users, 20);
    assertEquals(census.targets.replied_threads, 100);
    const selfEdges = census.graph.edges.filter((e) => e.kind === "self");
    assertEquals(selfEdges.length >= 1, true);
    assertEquals(census.graph.bias.self_weight > 0, true);
    assertEquals(census.graph.bias.independent_self_users, 1);
    assertEquals(census.graph.bias.star_share, 0);
  });
});

Deno.test("second member flips storage to migrate_before_keep", async () => {
  await withStore(async (store) => {
    const { user: alice } = await store.createOrgWithAdmin(
      { sub: "auth0|alice", email: "alice@acme.io" },
      { slug: "acme", handle: "alice@acme" },
    );
    const aliceAuth = store.authContextFromUser(alice);
    const inv = await store.createInvite(aliceAuth);
    await store.joinOrg(
      { sub: "auth0|bob", email: "bob@acme.io" },
      { invite_code: inv.code, handle: "bob@acme" },
    );

    const census = await store.listOpsCensus(ops(aliceAuth));
    assertEquals(census.users, 2);
    assertEquals(census.orgs_with_2plus_members, 1);
    assertEquals(census.storage_status, "migrate_before_keep");
    assertEquals(census.graph.nodes.filter((n) => n.kind === "user").length, 2);
  });
});

Deno.test("ops credits outstanding flips storage to migrate_before_keep", async () => {
  await withStore(async (store) => {
    const { user, org } = await store.createOrgWithAdmin(
      { sub: "auth0|solo", email: "solo@co.io" },
      { slug: "bill" },
    );
    await store.enterprise.topUpCredits(ops(store.authContextFromUser(user)), {
      org_id: org.id,
      amount_usd: "10.00",
      note: "pilot",
    });
    const census = await store.listOpsCensus(ops(store.authContextFromUser(user)));
    assertEquals(census.ledger_orgs_nonzero, 1);
    assertEquals(census.credits_outstanding_cents, 1000);
    assertEquals(census.storage_status, "migrate_before_keep");
  });
});

Deno.test("ops graph treats teammate mail as org star, own @all as self", async () => {
  await withStore(async (store) => {
    const { user: alice } = await store.createOrgWithAdmin(
      { sub: "auth0|alice", email: "alice@acme.io" },
      { slug: "acme", handle: "alice@acme" },
    );
    const aliceAuth = store.authContextFromUser(alice);
    await store.registerDevice(aliceAuth, { pubkey: "apk", platform: "macos" });
    await store.registerAgent(aliceAuth, { slug: "cursor" });
    await store.registerAgent(aliceAuth, { slug: "claude" });
    const inv = await store.createInvite(aliceAuth);
    const { user: bob } = await store.joinOrg(
      { sub: "auth0|bob", email: "bob@acme.io" },
      { invite_code: inv.code, handle: "bob@acme" },
    );
    const bobAuth = store.authContextFromUser(bob);
    await store.registerDevice(bobAuth, { pubkey: "bpk", platform: "macos" });
    await store.registerAgent(bobAuth, { slug: "cursor" });

    await store.createThread(aliceAuth, {
      to: "bob@acme",
      envelope: sampleEnvelope("hi"),
    });
    await store.createThread(aliceAuth, {
      to: "@all",
      envelope: sampleEnvelope("self"),
      from_agent: "cursor",
    });

    const census = await store.listOpsCensus(ops(aliceAuth));
    assertEquals(census.graph.bias.org_weight > 0, true);
    assertEquals(census.graph.bias.self_weight > 0, true);
    assertEquals(census.graph.bias.star_share, 1);
    assertEquals(census.graph.bias.hub_label, "alice@acme");
  });
});

Deno.test("GET /v1/admin/census is SuperAdmin-only", async () => {
  const kv = await Deno.openKv(":memory:");
  const { store, signToken } = await createStoreWithTestAuth(kv);
  const app = new Hono();
  app.onError((err) => handleHubError(err));
  app.route("/v1/orgs", createOrgRoutes(store));
  app.route("/v1/admin", createAdminRoutes(store));
  try {
    const token = await signToken({ sub: "auth0|pilot", email: "pilot@co.io" });
    await app.request("/v1/orgs", {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ slug: "co", name: "Co" }),
    });
    const forbidden = await app.request("/v1/admin/census", {
      headers: { Authorization: `Bearer ${token}` },
    });
    assertEquals(forbidden.status, 403);

    const opsToken = await signToken({
      sub: "auth0|pilot",
      email: "pilot@co.io",
      roles: ["SuperAdmin"],
    });
    const ok = await app.request("/v1/admin/census", {
      headers: { Authorization: `Bearer ${opsToken}` },
    });
    assertEquals(ok.status, 200);
    const body = await ok.json();
    assertEquals(body.users, 1);
    assertEquals(body.storage_status, "fresh_start_ok");
  } finally {
    kv.close();
  }
});
