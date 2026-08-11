import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { Hono } from "hono";
import { handleHubError } from "../middleware/auth.ts";
import { createAdminRoutes } from "./admin.ts";
import { createOrgRoutes } from "./orgs.ts";
import { createRegistryRoutes } from "./registry.ts";
import { createStoreWithTestAuth } from "../store/store.ts";
import { HubError } from "../store/errors.ts";

async function testApp() {
  const kv = await Deno.openKv(":memory:");
  const { store, signToken } = await createStoreWithTestAuth(kv);
  const app = new Hono();
  app.onError((err) => handleHubError(err));
  app.route("/v1/orgs", createOrgRoutes(store));
  app.route("/v1/registry", createRegistryRoutes(store));
  app.route("/v1/admin", createAdminRoutes(store));
  return { app, store, signToken, kv };
}

function bearer(token: string) {
  return { Authorization: `Bearer ${token}` };
}

async function onboard(
  app: Hono,
  signToken: (c: { sub: string; email: string; roles?: string[] }) => Promise<string>,
  sub: string,
  slug: string,
  email: string,
) {
  const token = await signToken({ sub, email });
  const res = await app.request("/v1/orgs", {
    method: "POST",
    headers: { ...bearer(token), "Content-Type": "application/json" },
    body: JSON.stringify({ slug, name: slug }),
  });
  assertEquals(res.status, 201);
  return token;
}

Deno.test("L4 draft → verify → publish; public list hides drafts", async () => {
  const { app, signToken, kv } = await testApp();
  try {
    const ownerToken = await onboard(
      app,
      signToken,
      "auth0|ent",
      "entco",
      "ops@entco.io",
    );

    const draftRes = await app.request("/v1/registry/drafts", {
      method: "POST",
      headers: { ...bearer(ownerToken), "Content-Type": "application/json" },
      body: JSON.stringify({
        address: "assistant@openai",
        price_usd: "0.10",
        capabilities: { models: ["gpt-4o"], modalities: ["text"] },
      }),
    });
    assertEquals(draftRes.status, 201);
    const { listing } = await draftRes.json();
    assertEquals(listing.status, "draft");
    assertEquals(listing.trust_tier, "enterprise");
    assertEquals(listing.visibility, "private");
    assertEquals(listing.billing.price_usd, "0.10");

    const pubEmpty = await app.request("/v1/registry");
    assertEquals(pubEmpty.status, 200);
    assertEquals((await pubEmpty.json()).listings.length, 0);

    const mine = await app.request("/v1/registry/mine", {
      headers: bearer(ownerToken),
    });
    assertEquals(mine.status, 200);
    assertEquals((await mine.json()).listings.length, 1);

    const opsToken = await signToken({
      sub: "auth0|ent",
      email: "ops@entco.io",
      roles: ["SuperAdmin"],
    });

    const publishTooSoon = await app.request(
      `/v1/admin/registry/${listing.id}/publish`,
      { method: "POST", headers: bearer(opsToken) },
    );
    assertEquals(publishTooSoon.status, 400);

    const verify = await app.request(
      `/v1/admin/registry/${listing.id}/verify`,
      {
        method: "POST",
        headers: { ...bearer(opsToken), "Content-Type": "application/json" },
        body: JSON.stringify({}),
      },
    );
    assertEquals(verify.status, 200);
    const verified = await verify.json();
    assertEquals(verified.listing.domain_verified, true);
    assertEquals(verified.listing.reserved_org_slug, "openai");

    const publish = await app.request(
      `/v1/admin/registry/${listing.id}/publish`,
      { method: "POST", headers: bearer(opsToken) },
    );
    assertEquals(publish.status, 200);
    assertEquals((await publish.json()).listing.status, "published");

    const pub = await app.request("/v1/registry");
    assertEquals((await pub.json()).listings.length, 1);

    const detail = await app.request("/v1/registry/listing/assistant%40openai");
    assertEquals(detail.status, 200);
    const body = await detail.json();
    assertEquals(body.listing.trust_tier, "enterprise");
    assertEquals(body.warn.trust_tier, "enterprise");
  } finally {
    kv.close();
  }
});

Deno.test("L4 debit + insufficient balance; suspend blocks send", async () => {
  const { app, store, signToken, kv } = await testApp();
  try {
    const ownerToken = await onboard(
      app,
      signToken,
      "auth0|vendor",
      "vendor",
      "v@vendor.io",
    );
    const customerToken = await onboard(
      app,
      signToken,
      "auth0|cust",
      "acme",
      "a@acme.io",
    );

    const draftRes = await app.request("/v1/registry/drafts", {
      method: "POST",
      headers: { ...bearer(ownerToken), "Content-Type": "application/json" },
      body: JSON.stringify({
        address: "bot@vendorbrand",
        price_usd: "1.00",
      }),
    });
    const { listing } = await draftRes.json();

    const opsToken = await signToken({
      sub: "auth0|vendor",
      email: "v@vendor.io",
      roles: ["SuperAdmin"],
    });
    await app.request(`/v1/admin/registry/${listing.id}/verify`, {
      method: "POST",
      headers: { ...bearer(opsToken), "Content-Type": "application/json" },
      body: "{}",
    });
    await app.request(`/v1/admin/registry/${listing.id}/publish`, {
      method: "POST",
      headers: bearer(opsToken),
    });

    const custAuth = await store.verifyAccessToken(customerToken);

    // Insufficient balance → nothing stored / debit fails.
    await assertRejects(
      () =>
        store.enterprise.debitEnterpriseOnStore(custAuth, {
          listing_id: listing.id,
          thread_id: crypto.randomUUID(),
          payload_bytes: 128,
        }),
      HubError,
      "Insufficient enterprise credits",
    );

    // top-up via ops
    const top = await app.request("/v1/admin/billing/credits", {
      method: "POST",
      headers: { ...bearer(opsToken), "Content-Type": "application/json" },
      body: JSON.stringify({
        org_id: custAuth.orgId,
        amount_usd: "5.00",
        note: "pilot grant",
      }),
    });
    assertEquals(top.status, 201);
    assertEquals((await top.json()).ledger.balance_cents, 500);

    const debit = await store.enterprise.debitEnterpriseOnStore(custAuth, {
      listing_id: listing.id,
      thread_id: crypto.randomUUID(),
      payload_bytes: 256,
      estimated_tokens: 64,
      blob_count: 1,
      latency_ms: 12,
    });
    assertEquals(debit.balance_cents, 400);
    assertEquals(debit.entry.kind, "debit");
    assertEquals(debit.metric.listing_id, listing.id);
    assertEquals(debit.metric.sender_org_id, custAuth.orgId);

    const suspend = await app.request(
      `/v1/admin/registry/${listing.id}/suspend`,
      { method: "POST", headers: bearer(opsToken) },
    );
    assertEquals(suspend.status, 200);
    assertEquals((await suspend.json()).listing.status, "suspended");

    await assertRejects(
      () =>
        store.enterprise.debitEnterpriseOnStore(custAuth, {
          listing_id: listing.id,
          thread_id: crypto.randomUUID(),
          payload_bytes: 10,
        }),
      HubError,
      "not accepting messages",
    );

    // Reserved slug blocks customer org create.
    await assertRejects(
      () => store.createOrg("vendorbrand", "Squatter"),
      HubError,
      "reserved for a verified enterprise",
    );
  } finally {
    kv.close();
  }
});

Deno.test("L4 createOrg rejects reserved enterprise slug", async () => {
  const { app, store, signToken, kv } = await testApp();
  try {
    const ownerToken = await onboard(
      app,
      signToken,
      "auth0|oai",
      "oaihold",
      "o@oai.io",
    );
    const draftRes = await app.request("/v1/registry/drafts", {
      method: "POST",
      headers: { ...bearer(ownerToken), "Content-Type": "application/json" },
      body: JSON.stringify({ address: "assistant@openai", price_usd: "0.05" }),
    });
    const { listing } = await draftRes.json();
    const opsToken = await signToken({
      sub: "auth0|oai",
      email: "o@oai.io",
      roles: ["SuperAdmin"],
    });
    await app.request(`/v1/admin/registry/${listing.id}/verify`, {
      method: "POST",
      headers: { ...bearer(opsToken), "Content-Type": "application/json" },
      body: "{}",
    });

    const squatter = await signToken({
      sub: "auth0|squat",
      email: "s@x.io",
    });
    const res = await app.request("/v1/orgs", {
      method: "POST",
      headers: { ...bearer(squatter), "Content-Type": "application/json" },
      body: JSON.stringify({ slug: "openai" }),
    });
    assertEquals(res.status, 409);
  } finally {
    kv.close();
  }
});
