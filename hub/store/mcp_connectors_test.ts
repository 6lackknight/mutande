import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { HubError } from "./errors.ts";
import { createStoreWithTestAuth } from "./store.ts";
import {
  isMcpConnectorToken,
  MAX_MCP_CONNECTORS,
  MCP_CONNECTOR_PREFIX,
} from "./mcp_connectors.ts";

async function withStore(
  fn: (ctx: {
    store: Awaited<ReturnType<typeof createStoreWithTestAuth>>["store"];
    signToken: Awaited<ReturnType<typeof createStoreWithTestAuth>>["signToken"];
  }) => Promise<void>,
) {
  const kv = await Deno.openKv(":memory:");
  const { store, signToken } = await createStoreWithTestAuth(kv);
  try {
    await fn({ store, signToken });
  } finally {
    kv.close();
  }
}

Deno.test("isMcpConnectorToken requires mtc_ prefix", () => {
  assertEquals(isMcpConnectorToken("mtc_" + "a".repeat(16)), true);
  assertEquals(isMcpConnectorToken("mtc_short"), false);
  assertEquals(isMcpConnectorToken("not-a-connector"), false);
});

Deno.test("mint connector key then AuthContext from token", async () => {
  await withStore(async ({ store }) => {
    const { user } = await store.createOrgWithAdmin(
      { sub: "auth0|alice", email: "alice@acme.test" },
      { slug: "acme", name: "Acme", handle: "alice@acme" },
    );
    const auth = store.authContextFromUser(user);
    const minted = await store.mintMcpConnector(auth, { label: "Grok Bot" });
    assertEquals(minted.token.startsWith(MCP_CONNECTOR_PREFIX), true);
    assertEquals(isMcpConnectorToken(minted.token), true);
    assertEquals(minted.connector.slug, "grok");
    assertEquals(minted.connector.label, "Grok Bot");
    assertEquals(minted.connector.prefix, minted.token.slice(0, 12));

    const ctx = await store.verifyAccessToken(minted.token);
    assertEquals(ctx.userId, user.id);
    assertEquals(ctx.handle, "alice@acme");
    assertEquals(ctx.auth0Sub, "auth0|alice");

    const claims = await store.verifyAuth0Claims(minted.token);
    assertEquals(claims.sub, "auth0|alice");
    assertEquals(claims.email, "alice@acme.test");

    const listed = await store.listMcpConnectors(auth);
    assertEquals(listed.connectors.length, 1);
    assertEquals(listed.connectors[0]!.id, minted.connector.id);
    assertEquals(
      JSON.stringify(listed).includes(minted.token.slice(MCP_CONNECTOR_PREFIX.length)),
      false,
    );
  });
});

Deno.test("revoke connector invalidates token", async () => {
  await withStore(async ({ store }) => {
    const { user } = await store.createOrgWithAdmin(
      { sub: "auth0|bob", email: "bob@acme.test" },
      { slug: "acme", name: "Acme", handle: "bob@acme" },
    );
    const auth = store.authContextFromUser(user);
    const minted = await store.mintMcpConnector(auth, { slug: "grok" });
    await store.revokeMcpConnector(auth, minted.connector.id);
    await assertRejects(
      () => store.verifyAccessToken(minted.token),
      HubError,
      "Invalid or expired token",
    );
    assertEquals((await store.listMcpConnectors(auth)).connectors.length, 0);
  });
});

Deno.test("mint slug override and empty slug", async () => {
  await withStore(async ({ store }) => {
    const { user } = await store.createOrgWithAdmin(
      { sub: "auth0|cara", email: "cara@acme.test" },
      { slug: "acme", name: "Acme", handle: "cara@acme" },
    );
    const auth = store.authContextFromUser(user);
    const claude = await store.mintMcpConnector(auth, { slug: "claude", label: "Claude" });
    assertEquals(claude.connector.slug, "claude");
    const none = await store.mintMcpConnector(auth, { slug: "", label: "none" });
    assertEquals(none.connector.slug, null);
  });
});

Deno.test("max connector keys", async () => {
  await withStore(async ({ store }) => {
    const { user } = await store.createOrgWithAdmin(
      { sub: "auth0|max", email: "max@acme.test" },
      { slug: "acme", name: "Acme", handle: "max@acme" },
    );
    const auth = store.authContextFromUser(user);
    for (let i = 0; i < MAX_MCP_CONNECTORS; i++) {
      await store.mintMcpConnector(auth, { label: `k${i}` });
    }
    await assertRejects(
      () => store.mintMcpConnector(auth, { label: "one-too-many" }),
      HubError,
      "Too many MCP connector keys",
    );
  });
});

Deno.test("unknown connector token is unauthorized", async () => {
  await withStore(async ({ store }) => {
    await assertRejects(
      () => store.verifyAccessToken(`${MCP_CONNECTOR_PREFIX}${"x".repeat(32)}`),
      HubError,
      "Invalid or expired token",
    );
  });
});
