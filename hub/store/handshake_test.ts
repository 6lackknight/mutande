import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { HubError } from "./errors.ts";
import { looksSecretOrPath, sanitizeHandshake } from "./handshake.ts";
import { createStoreWithTestAuth } from "./store.ts";
import type { Auth0Claims } from "./types.ts";

Deno.test("sanitizeHandshake strips secrets and paths", () => {
  const card = sanitizeHandshake(
    {
      host: "Cursor",
      models: ["Composer", "sk-live-secret", "~/keys"],
      other_tools: ["github", "Bearer abc.def"],
      ask_me_about: ["routing", "api_key=foo"],
      preferred_file_format: "markdown",
    },
    "2026-08-19T12:00:00.000Z",
  );
  assertEquals(card.host, "Cursor");
  assertEquals(card.models, ["Composer"]);
  assertEquals(card.other_tools, ["github"]);
  assertEquals(card.ask_me_about, ["routing"]);
  assertEquals(card.preferred_file_format, "markdown");
  assertEquals(card.published_at, "2026-08-19T12:00:00.000Z");
});

Deno.test("looksSecretOrPath catches common leaks", () => {
  assertEquals(looksSecretOrPath("sk-abc"), true);
  assertEquals(looksSecretOrPath("/Users/me/secret"), true);
  assertEquals(looksSecretOrPath("markdown"), false);
});

Deno.test("handshake profile is org-visible and owner-writable", async () => {
  const kv = await Deno.openKv(":memory:");
  const { store } = await createStoreWithTestAuth(kv);
  try {
    const { user: alice } = await store.createOrgWithAdmin(
      { sub: "auth0|alice", email: "alice@example.com" } satisfies Auth0Claims,
      { slug: "acme", name: "Acme", handle: "alice@acme" },
    );
    const invite = await store.createInvite(store.authContextFromUser(alice));
    const { user: bob } = await store.joinOrg(
      { sub: "auth0|bob", email: "bob@example.com" },
      { invite_code: invite.code, handle: "bob@acme" },
    );
    const { user: eve } = await store.createOrgWithAdmin(
      { sub: "auth0|eve", email: "eve@other.com" },
      { slug: "other", name: "Other", handle: "eve@other" },
    );

    const aliceAuth = store.authContextFromUser(alice);
    const bobAuth = store.authContextFromUser(bob);
    const eveAuth = store.authContextFromUser(eve);

    const cursor = await store.registerAgent(aliceAuth, { slug: "cursor" });
    const updated = await store.putAgentHandshake(aliceAuth, cursor.id, {
      host: "Cursor",
      models: ["Composer"],
      skills: ["mutande", "handshake"],
      ask_me_about: ["routing"],
      preferred_file_format: "markdown",
      other_tools: ["github"],
    });
    assertEquals(updated.handshake?.host, "Cursor");
    assertEquals(updated.handshake?.models?.[0], "Composer");

    const asBob = await store.getAgentHandshake(bobAuth, cursor.id);
    assertEquals(asBob.handshake?.address, undefined);
    assertEquals(asBob.handshake?.host, "Cursor");

    await assertRejects(
      () => store.putAgentHandshake(bobAuth, cursor.id, { host: "nope" }),
      HubError,
      "owner",
    );
    await assertRejects(
      () => store.getAgentHandshake(eveAuth, cursor.id),
      HubError,
      "visible",
    );
  } finally {
    kv.close();
  }
});
