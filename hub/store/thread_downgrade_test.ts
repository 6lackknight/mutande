import { assertEquals, assertExists, assertRejects } from "jsr:@std/assert@1";
import { HubError } from "./errors.ts";
import {
  createStoreWithTestAuth,
  type HubStore,
} from "./store.ts";
import type { Auth0Claims, Envelope } from "./types.ts";
import { downgradePromptCopy, messageVisibleAfterDowngrade } from "./thread_downgrade.ts";

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

async function setupOrgWithUsers(store: HubStore) {
  const { user: alice } = await store.createOrgWithAdmin(
    { sub: "auth0|alice", email: "alice@example.com" } as Auth0Claims,
    { slug: "acme", name: "Acme", handle: "alice@acme" },
  );
  const inv1 = await store.createInvite(store.authContextFromUser(alice));
  const { user: bob } = await store.joinOrg(
    { sub: "auth0|bob", email: "bob@example.com" } as Auth0Claims,
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

Deno.test("L5 prompt copy", () => {
  assertEquals(
    downgradePromptCopy("chatgpt"),
    "Adding @chatgpt (web) ends E2E for this thread",
  );
});

Deno.test("L5 unanimous approve flips mode + divider; history sealed for web", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    await store.connectAgent(bobAuth, "mcp", { slug: "chatgpt" });

    const { thread, message_id: e2eMsgId } = await store.createThread(aliceAuth, {
      to: "bob@acme/claude",
      envelope: sampleEnvelope("e2e-op"),
    });
    assertEquals(thread.encryption_mode, "e2e");

    // Alice proposes adding Bob's web agent.
    const { proposal, prompt } = await store.proposeThreadDowngrade(
      aliceAuth,
      thread.id,
      { agent_slug: "chatgpt", from_agent: "cursor" },
    );
    assertEquals(prompt.includes("@chatgpt (web)"), true);
    assertEquals(proposal.status, "pending");
    // Alice's sidecar agents auto-approved; Bob still needs to approve.
    assertEquals(proposal.approvals.length > 0, true);
    assertEquals(proposal.status, "pending");

    const pending = await store.listPendingThreadDowngrades(bobAuth);
    assertEquals(pending.proposals.some((p) => p.id === proposal.id), true);

    const { proposal: approved, thread: downgraded } = await store
      .approveThreadDowngrade(bobAuth, thread.id, proposal.id);
    assertEquals(approved.status, "approved");
    assertEquals(downgraded.encryption_mode, "app_envelope");
    assertExists(downgraded.downgrade_point);
    assertEquals(downgraded.downgrade_point!.message_id, approved.divider_message_id);
    assertEquals(downgraded.audience_agent_id, proposal.proposed_agent_id);

    const detail = await store.getThread(bobAuth, thread.id);
    const divider = detail.messages.find((m) =>
      m.id === downgraded.downgrade_point!.message_id
    );
    assertExists(divider);
    assertEquals(divider!.content_store, "app_envelope");
    assertEquals(
      divider!.app_envelope?.notes,
      "E2E ended here — @chatgpt (web) added, approved by all",
    );

    // Pre-downgrade E2E message still present for sidecar getThread.
    assertEquals(detail.messages.some((m) => m.id === e2eMsgId), true);
    assertEquals(
      detail.messages.find((m) => m.id === e2eMsgId)?.content_store,
      "e2e",
    );

    // Web pull: only join-point onward (history sealed).
    const webPull = await store.fetchAppMessages(bobAuth, thread.id, {
      agent_id: proposal.proposed_agent_id,
    });
    assertEquals(webPull.messages.some((m) => m.id === e2eMsgId), false);
    assertEquals(
      webPull.messages.some((m) => m.id === downgraded.downgrade_point!.message_id),
      true,
    );

    // Web agent can now reply with app_envelope.
    const { message_id: replyId } = await store.postReply(bobAuth, thread.id, {
      app_envelope: { version: 1, notes: "hello from web" },
      from_agent: "chatgpt",
    });
    const after = await store.fetchAppMessages(bobAuth, thread.id);
    assertEquals(after.messages.some((m) => m.id === replyId), true);

    // One-way ratchet — cannot propose again.
    await assertRejects(
      () =>
        store.proposeThreadDowngrade(aliceAuth, thread.id, {
          agent_slug: "chatgpt",
        }),
      HubError,
      "already non-E2E",
    );
  });
});

Deno.test("L5 any deny keeps thread E2E", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth, bobAuth } = await setupOrgWithUsers(store);
    await store.connectAgent(bobAuth, "mcp", { slug: "chatgpt" });

    const { thread } = await store.createThread(aliceAuth, {
      to: "bob@acme/claude",
      envelope: sampleEnvelope("deny-path"),
    });

    const { proposal } = await store.proposeThreadDowngrade(aliceAuth, thread.id, {
      agent_slug: "chatgpt",
    });
    assertEquals(proposal.status, "pending");

    const { proposal: denied } = await store.denyThreadDowngrade(
      bobAuth,
      thread.id,
      proposal.id,
    );
    assertEquals(denied.status, "denied");

    const detail = await store.getThread(aliceAuth, thread.id);
    assertEquals(detail.thread.encryption_mode, "e2e");
    assertEquals(detail.thread.downgrade_point, undefined);

    // Web still cannot reply on E2E.
    await assertRejects(
      () =>
        store.postReply(bobAuth, thread.id, {
          app_envelope: { version: 1, notes: "nope" },
          from_agent: "chatgpt",
        }),
      HubError,
      "downgrade",
    );

    // Can propose again after deny.
    const again = await store.proposeThreadDowngrade(aliceAuth, thread.id, {
      agent_slug: "chatgpt",
    });
    assertEquals(again.proposal.status, "pending");
  });
});

Deno.test("L5 sole sidecar proposer auto-finalizes", async () => {
  await withTestStore(async ({ store }) => {
    const { aliceAuth } = await setupOrgWithUsers(store);
    await store.connectAgent(aliceAuth, "mcp", { slug: "chatgpt" });
    await store.registerAgent(aliceAuth, { slug: "claude" });

    const { thread } = await store.createThread(aliceAuth, {
      to: "alice@acme/claude",
      envelope: sampleEnvelope("self"),
    });
    assertEquals(thread.encryption_mode, "e2e");

    // Only Alice's sidecar agents are required — proposing auto-approves them all.
    const { proposal } = await store.proposeThreadDowngrade(aliceAuth, thread.id, {
      agent_slug: "chatgpt",
      from_agent: "cursor",
    });
    assertEquals(proposal.status, "approved");

    const detail = await store.getThread(aliceAuth, thread.id);
    assertEquals(detail.thread.encryption_mode, "app_envelope");
    assertExists(detail.thread.downgrade_point);
  });
});

Deno.test("L5 messageVisibleAfterDowngrade seals E2E history", () => {
  const thread = {
    id: "t",
    kind: "direct" as const,
    status: "open" as const,
    from: "a@acme/cursor",
    from_user_id: "u1",
    audience: "a@acme/chatgpt",
    org_id: "o",
    participant_count: 2,
    reply_count: 1,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-01T00:00:00.000Z",
    encryption_mode: "app_envelope" as const,
    downgrade_point: {
      message_id: "divider",
      approvers: ["a1"],
    },
  };
  const e2e = {
    id: "old",
    thread_id: "t",
    from_user_id: "u1",
    from_handle: "a@acme/cursor",
    content_store: "e2e" as const,
    created_at: "2026-01-01T00:00:00.000Z",
    envelope: sampleEnvelope(),
  };
  const divider = {
    id: "divider",
    thread_id: "t",
    from_user_id: "system",
    from_handle: "mutande",
    content_store: "app_envelope" as const,
    created_at: "2026-01-01T00:01:00.000Z",
  };
  assertEquals(messageVisibleAfterDowngrade(thread, e2e), false);
  assertEquals(messageVisibleAfterDowngrade(thread, divider), true);
});

Deno.test("L2 web cannot reply to E2E without approve (still gated)", async () => {
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
    );
  });
});
