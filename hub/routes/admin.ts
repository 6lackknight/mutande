import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";
import type { TopUpCreditsInput } from "../store/types.ts";

export function createAdminRoutes(store: HubStore) {
  const adminRoutes = new Hono<HubEnv>();
  adminRoutes.use("*", authMiddleware(store));
  adminRoutes.get("/invites", async (c) => {
    return c.json(await store.listInvitesAsAdmin(c.get("auth")));
  });
  adminRoutes.post("/invites", async (c) => {
    let email: string | undefined;
    try {
      const body = await c.req.json() as { email?: unknown };
      if (typeof body.email === "string" && body.email.trim()) {
        email = body.email.trim();
      }
    } catch {
      // empty body is fine
    }
    const invite = await store.createInviteAsAdmin(c.get("auth"), { email });
    return c.json({ invite }, 201);
  });
  adminRoutes.get("/feedback", async (c) => {
    return c.json(await store.listFeedback(c.get("auth")));
  });
  adminRoutes.get("/waitlist", async (c) => {
    return c.json(await store.listWaitlist(c.get("auth")));
  });
  adminRoutes.get("/census", async (c) => {
    return c.json(await store.listOpsCensus(c.get("auth")));
  });
  adminRoutes.get("/pairing-flags", async (c) => {
    return c.json(await store.listPairingOpsFlags(c.get("auth")));
  });

  // ── L4 enterprise ops ──────────────────────────────────────────────────
  adminRoutes.get("/registry", async (c) => {
    return c.json(await store.enterprise.listAllForOps(c.get("auth")));
  });
  adminRoutes.post("/registry/:id/verify", async (c) => {
    let org_slug: string | undefined;
    try {
      const body = await c.req.json() as { org_slug?: unknown };
      if (typeof body.org_slug === "string" && body.org_slug.trim()) {
        org_slug = body.org_slug.trim();
      }
    } catch {
      // empty body — use address org slug
    }
    const listing = await store.enterprise.verifyAndReserveSlug(
      c.get("auth"),
      c.req.param("id")!,
      org_slug,
    );
    return c.json({ listing });
  });
  adminRoutes.post("/registry/:id/publish", async (c) => {
    const listing = await store.enterprise.publishListing(
      c.get("auth"),
      c.req.param("id")!,
    );
    return c.json({ listing });
  });
  adminRoutes.post("/registry/:id/suspend", async (c) => {
    const listing = await store.enterprise.suspendListing(
      c.get("auth"),
      c.req.param("id")!,
    );
    return c.json({ listing });
  });
  adminRoutes.post("/registry/:id/unpublish", async (c) => {
    const listing = await store.enterprise.unpublishListing(
      c.get("auth"),
      c.req.param("id")!,
    );
    return c.json({ listing });
  });
  adminRoutes.post("/billing/credits", async (c) => {
    const body = await c.req.json<TopUpCreditsInput>();
    const result = await store.enterprise.topUpCredits(c.get("auth"), body);
    return c.json(result, 201);
  });
  adminRoutes.get("/billing/ledger/:orgId", async (c) => {
    await store.enterprise.listAllForOps(c.get("auth"));
    const ledger = await store.enterprise.getLedger(c.req.param("orgId")!);
    return c.json({ ledger });
  });
  adminRoutes.get("/enterprise/metrics", async (c) => {
    const limitRaw = c.req.query("limit");
    const limit = limitRaw ? Number(limitRaw) : undefined;
    return c.json(
      await store.enterprise.listMetrics(c.get("auth"), {
        limit: Number.isFinite(limit) ? limit : undefined,
      }),
    );
  });

  return adminRoutes;
}
