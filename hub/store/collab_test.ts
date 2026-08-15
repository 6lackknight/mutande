import { assertEquals, assertExists, assertRejects } from "jsr:@std/assert@1";
import { HubError } from "./errors.ts";
import { HubStore, createStoreWithTestAuth } from "./store.ts";
import {
  DEFAULT_LIST_NAMES,
  insertLanePosition,
  laneGapExhausted,
  last84ActivityDays,
  LANE_MIN_GAP,
  rebalancePositions,
} from "./collab.ts";
import type { Auth0Claims, Envelope } from "./types.ts";

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

async function setupOrg(store: HubStore) {
  const { user: alice } = await store.createOrgWithAdmin(
    { sub: "auth0|alice", email: "alice@example.com" },
    { slug: "acme", name: "Acme", handle: "alice@acme" },
  );
  const inv = await store.createInvite(store.authContextFromUser(alice));
  const { user: bob } = await store.joinOrg(
    { sub: "auth0|bob", email: "bob@example.com" },
    { invite_code: inv.code, handle: "bob@acme" },
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
    alice,
    bob,
  };
}

Deno.test("lane midpoint insert and rebalance helpers", () => {
  assertEquals(insertLanePosition(), 1024);
  assertEquals(insertLanePosition(1024), 2048);
  assertEquals(insertLanePosition(undefined, 1024), 512);
  assertEquals(insertLanePosition(1024, 2048), 1536);
  assertEquals(laneGapExhausted(1, 1 + LANE_MIN_GAP / 2), true);
  assertEquals(laneGapExhausted(0, 1024), false);
  assertEquals(rebalancePositions(3), [1024, 2048, 3072]);
});

Deno.test("last84ActivityDays fills UTC window", () => {
  const now = new Date("2026-08-15T18:00:00Z");
  const days = last84ActivityDays(new Map([["2026-08-15", 3]]), now);
  assertEquals(days.length, 84);
  assertEquals(days[0].date, "2026-05-24");
  assertEquals(days[83].date, "2026-08-15");
  assertEquals(days[83].count, 3);
  assertEquals(days[82].count, 0);
});

Deno.test("create collab derives e2e from sidecar roster", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrg(store);
    const collab = await store.createCollab(aliceAuth, {
      name: "Launch",
      roster_addresses: ["@cursor"],
    });
    assertEquals(collab.encryption_mode, "e2e");
    assertEquals(collab.schema_version, 1);
    assertEquals(collab.lists.map((l) => l.name), [...DEFAULT_LIST_NAMES]);
    assertEquals(collab.roster.length, 1);
    assertEquals(collab.roster[0].address, "alice@acme/cursor");
    assertEquals(collab.steerer_user_ids, [aliceAuth.userId]);
    assertExists(collab.memory_thread_id);
    assertEquals(collab.card_count, 0);
    const mem = await store.getThread(aliceAuth, collab.memory_thread_id);
    assertEquals(mem.thread.encryption_mode, "e2e");
  });
});

Deno.test("create collab derives app_envelope from hosted roster", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrg(store);
    await store.connectAgent(aliceAuth, "mcp", { slug: "chatgpt" });
    await store.setTransportDefault(aliceAuth, {
      slug: "chatgpt",
      transport: "mcp",
    });
    const collab = await store.createCollab(aliceAuth, {
      name: "Web board",
      roster_addresses: ["@chatgpt"],
      instructions: "Ship the alpha.",
    });
    assertEquals(collab.encryption_mode, "app_envelope");
    assertEquals(collab.instructions, "Ship the alpha.");
    assertEquals(collab.roster[0].transport, "mcp");
  });
});

Deno.test("adding an agent auto-adds its human as steerer", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth, bob } = await setupOrg(store);
    const collab = await store.createCollab(aliceAuth, {
      name: "Pair",
      roster_addresses: ["bob@acme/claude"],
    });
    assertEquals(collab.steerer_user_ids.includes(bob.id), true);
    assertEquals(collab.steerer_joins.length, 2);
    const listed = await store.listCollabs(bobAuth);
    assertEquals(listed.collabs.length, 1);
  });
});

Deno.test("roster unique per agent_id", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrg(store);
    await assertRejects(
      () =>
        store.createCollab(aliceAuth, {
          name: "Dup",
          roster_addresses: ["@cursor", "alice@acme/cursor"],
        }),
      HubError,
      "Roster already includes",
    );
  });
});

Deno.test("instructions XOR sealed by encryption mode", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrg(store);
    await assertRejects(
      () =>
        store.createCollab(aliceAuth, {
          name: "Bad e2e",
          roster_addresses: ["@cursor"],
          instructions: "plaintext not allowed",
        }),
      HubError,
      "cannot store plaintext instructions",
    );

    await store.connectAgent(aliceAuth, "mcp", { slug: "chatgpt" });
    await store.setTransportDefault(aliceAuth, {
      slug: "chatgpt",
      transport: "mcp",
    });
    await assertRejects(
      () =>
        store.createCollab(aliceAuth, {
          name: "Bad web",
          roster_addresses: ["@chatgpt"],
          instructions_sealed: {
            envelope_id: crypto.randomUUID(),
            updated_by: aliceAuth.userId,
          },
        }),
      HubError,
      "cannot store sealed instructions",
    );

    await assertRejects(
      () =>
        store.createCollab(aliceAuth, {
          name: "Both",
          roster_addresses: ["@chatgpt"],
          instructions: "x",
          instructions_sealed: {
            envelope_id: crypto.randomUUID(),
            updated_by: aliceAuth.userId,
          },
        }),
      HubError,
      "cannot both be set",
    );
  });
});

Deno.test("non-member cannot get_collab", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrg(store);
    const collab = await store.createCollab(aliceAuth, { name: "Private" });
    await assertRejects(
      () => store.getCollab(bobAuth, collab.id),
      HubError,
      "Not a collab member",
    );
  });
});

Deno.test("card create wraps to all steerers; set_lane leaves status", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bob, bobAuth } = await setupOrg(store);
    const collab = await store.createCollab(aliceAuth, {
      name: "Board",
      steerer_handles: ["bob@acme"],
      instructions_sealed: undefined,
      roster_addresses: ["@cursor", "bob@acme/claude"],
    });
    const backlog = collab.lists[0];
    const doing = collab.lists[1];
    const { thread } = await store.createThread(aliceAuth, {
      to: "bob@acme/claude",
      envelope: sampleEnvelope("card"),
      collab_id: collab.id,
    });
    assertEquals(thread.collab_id, collab.id);
    assertEquals(thread.lane_id, backlog.id);
    assertEquals(thread.status, "open");
    assertEquals(thread.encryption_mode, "e2e");
    assertEquals(thread.participant_user_ids?.includes(bob.id), true);

    const moved = await store.setLane(aliceAuth, collab.id, {
      thread_id: thread.id,
      lane_id: doing.id,
    });
    assertEquals(moved.thread.lane_id, doing.id);
    assertEquals(moved.thread.status, "open");

    const closed = await store.closeThread(aliceAuth, thread.id);
    assertEquals(closed.thread.status, "closed");
    assertEquals(closed.thread.lane_id, doing.id);

    const bobSees = await store.getThread(bobAuth, thread.id);
    assertEquals(bobSees.thread.id, thread.id);
  });
});

Deno.test("set_lane inserts at midpoint without touching status", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrg(store);
    await store.connectAgent(aliceAuth, "mcp", { slug: "chatgpt" });
    await store.setTransportDefault(aliceAuth, {
      slug: "chatgpt",
      transport: "mcp",
    });
    const collab = await store.createCollab(aliceAuth, {
      name: "Gaps",
      roster_addresses: ["@chatgpt"],
      instructions: "",
    });
    const lane = collab.lists[0].id;
    const a = await store.createThread(aliceAuth, {
      to: "alice@acme",
      app_envelope: { version: 1, notes: "a" },
      collab_id: collab.id,
      lane_id: lane,
    });
    const c = await store.createThread(aliceAuth, {
      to: "alice@acme",
      app_envelope: { version: 1, notes: "c" },
      collab_id: collab.id,
      lane_id: lane,
    });
    const b = await store.createThread(aliceAuth, {
      to: "alice@acme",
      app_envelope: { version: 1, notes: "b" },
      collab_id: collab.id,
      lane_id: lane,
    });
    const moved = await store.setLane(aliceAuth, collab.id, {
      thread_id: b.thread.id,
      lane_id: lane,
      before_thread_id: c.thread.id,
    });
    assertEquals(moved.thread.status, "open");
    const pos = moved.thread.lane_position ?? 0;
    assertEquals(pos > (a.thread.lane_position ?? 0), true);
    assertEquals(pos < (c.thread.lane_position ?? 0), true);
  });
});

Deno.test("downgrade_point is immutable once set", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bob } = await setupOrg(store);
    const collab = await store.createCollab(aliceAuth, {
      name: "Seal",
      steerer_handles: ["bob@acme"],
      roster_addresses: ["@cursor"],
    });
    const flipped = await store.applyCollabDowngrade(aliceAuth, collab.id, {
      cause_address: "bob@acme/chatgpt",
      approvers: [aliceAuth.userId, bob.id],
    });
    assertEquals(flipped.encryption_mode, "app_envelope");
    assertExists(flipped.downgrade_point);
    await assertRejects(
      () =>
        store.applyCollabDowngrade(aliceAuth, collab.id, {
          cause_address: "other@acme/chatgpt",
          approvers: [aliceAuth.userId, bob.id],
        }),
      HubError,
      "immutable",
    );
  });
});

Deno.test("steerer joins are append-only; removal is forward-only", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bob, bobAuth } = await setupOrg(store);
    const collab = await store.createCollab(aliceAuth, { name: "Room" });
    const joined = await store.addCollabSteerer(aliceAuth, collab.id, {
      handle: "bob@acme",
    });
    assertEquals(joined.steerer_joins.length, 2);
    const joinAt = joined.steerer_joins[1].joined_at;

    const removed = await store.removeCollabSteerer(aliceAuth, collab.id, {
      user_id: bob.id,
    });
    assertEquals(removed.steerer_user_ids.includes(bob.id), false);
    assertEquals(removed.steerer_joins[1].joined_at, joinAt);
    assertEquals(removed.steerer_removals?.length, 1);

    await assertRejects(
      () => store.getCollab(bobAuth, collab.id),
      HubError,
      "Not a collab member",
    );
    await assertRejects(
      () =>
        store.removeCollabSteerer(aliceAuth, collab.id, {
          user_id: aliceAuth.userId,
        }),
      HubError,
      "Cannot remove the collab creator",
    );
  });
});

Deno.test("add_learning authorized to creator side only; hosted rejected on e2e", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrg(store);
    const collab = await store.createCollab(aliceAuth, {
      name: "Brain",
      steerer_handles: ["bob@acme"],
      roster_addresses: ["@cursor", "bob@acme/claude"],
    });

    await assertRejects(
      () =>
        store.addLearning(bobAuth, collab.id, { notes: "bob diary" }),
      HubError,
      "creator's side",
    );

    const mcp = await store.connectAgent(aliceAuth, "mcp", { slug: "chatgpt" });
    await assertRejects(
      () =>
        store.addLearning(aliceAuth, collab.id, {
          notes: "from web",
          from_agent_id: mcp.id,
          envelope: sampleEnvelope("learn"),
        }),
      HubError,
      "Hosted agents cannot write the brain",
    );

    const added = await store.addLearning(aliceAuth, collab.id, {
      notes: "Prefer AskQuestion for product calls.",
      envelope: sampleEnvelope("learn"),
    });
    assertExists(added.message_id);

    const web = await store.createCollab(aliceAuth, {
      name: "Web brain",
      roster_addresses: ["@chatgpt"],
      instructions: "Keep it short.",
    });
    const learning = await store.addLearning(aliceAuth, web.id, {
      notes: "One-liner.",
      from_agent: "chatgpt",
    });
    assertExists(learning.message_id);
    const view = await store.getCollab(aliceAuth, web.id);
    assertEquals(view.learnings.length, 1);
    assertEquals(view.learnings[0].notes, "One-liner.");
  });
});

Deno.test("card_count is derived from indexed threads", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrg(store);
    await store.connectAgent(aliceAuth, "mcp", { slug: "chatgpt" });
    await store.setTransportDefault(aliceAuth, {
      slug: "chatgpt",
      transport: "mcp",
    });
    const collab = await store.createCollab(aliceAuth, {
      name: "Count",
      roster_addresses: ["@chatgpt"],
      instructions: "",
    });
    await store.createThread(aliceAuth, {
      to: "alice@acme",
      app_envelope: { version: 1, notes: "one" },
      collab_id: collab.id,
    });
    await store.createThread(aliceAuth, {
      to: "alice@acme",
      app_envelope: { version: 1, notes: "two" },
      collab_id: collab.id,
    });
    const got = await store.getCollab(aliceAuth, collab.id);
    assertEquals(got.card_count, 2);
    assertEquals(got.cards.length, 2);
    const listed = await store.listCollabs(aliceAuth);
    assertEquals(listed.collabs[0].card_count, 2);
    assertEquals(listed.collabs[0].open, 2);
    assertEquals(listed.portfolio.totals.open, 2);
    assertEquals(listed.portfolio.activity.length, 84);
  });
});

Deno.test("list collabs portfolio buckets lanes, needs-you, and activity", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrg(store);
    const collab = await store.createCollab(aliceAuth, {
      name: "Dash",
      steerer_handles: ["bob@acme"],
      roster_addresses: ["@cursor"],
    });
    const doing = collab.lists[1];
    const done = collab.lists[2];
    await store.createThread(aliceAuth, {
      to: "bob@acme",
      envelope: sampleEnvelope("backlog"),
      collab_id: collab.id,
    });
    await store.createThread(aliceAuth, {
      to: "alice@acme",
      envelope: sampleEnvelope("doing"),
      collab_id: collab.id,
      lane_id: doing.id,
    });
    const closed = await store.createThread(aliceAuth, {
      to: "alice@acme",
      envelope: sampleEnvelope("done"),
      collab_id: collab.id,
      lane_id: done.id,
    });
    await store.closeThread(aliceAuth, closed.thread.id);

    const aliceList = await store.listCollabs(aliceAuth);
    assertEquals(aliceList.collabs.length, 1);
    assertEquals(aliceList.collabs[0].card_count, 3);
    assertEquals(aliceList.collabs[0].open, 2);
    assertEquals(aliceList.collabs[0].doing, 1);
    assertEquals(aliceList.portfolio.totals.collabs, 1);
    assertEquals(aliceList.portfolio.totals.open, 2);
    assertEquals(aliceList.portfolio.totals.doing, 1);
    assertEquals(aliceList.portfolio.lane_totals.backlog, 1);
    assertEquals(aliceList.portfolio.lane_totals.doing, 1);
    assertEquals(aliceList.portfolio.lane_totals.done, 0);
    const today = new Date().toISOString().slice(0, 10);
    const day = aliceList.portfolio.activity.find((d) => d.date === today);
    assertEquals(day?.count, 3);
    assertEquals(aliceList.collabs[0].cards.length, 0);

    const bobList = await store.listCollabs(bobAuth);
    assertEquals(bobList.collabs[0].needs_you, 2);
    assertEquals(bobList.portfolio.totals.needs_you, 2);
    assertEquals(aliceList.collabs[0].needs_you ?? 0, 0);
  });
});
