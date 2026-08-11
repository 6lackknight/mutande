import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";
import type {
  CreateRegistryDraftInput,
  UpdateRegistryDraftInput,
} from "../store/types.ts";

/**
 * Public enterprise registry (§8).
 * Drafts are submitter-org only; GET / lists published; GET /:id|address exposes trust_tier for warn banners.
 */
export function createRegistryRoutes(store: HubStore) {
  const routes = new Hono<HubEnv>();

  routes.get("/", async (c) => {
    return c.json(await store.enterprise.listPublished());
  });

  routes.get("/mine", authMiddleware(store), async (c) => {
    return c.json(await store.enterprise.listMine(c.get("auth")));
  });

  routes.post("/drafts", authMiddleware(store), async (c) => {
    const body = await c.req.json<CreateRegistryDraftInput>();
    const listing = await store.enterprise.createDraft(c.get("auth"), body);
    return c.json({ listing }, 201);
  });

  routes.patch("/drafts/:id", authMiddleware(store), async (c) => {
    const body = await c.req.json<UpdateRegistryDraftInput>();
    const listing = await store.enterprise.updateDraft(
      c.get("auth"),
      c.req.param("id")!,
      body,
    );
    return c.json({ listing });
  });

  routes.get("/billing", authMiddleware(store), async (c) => {
    const ledger = await store.enterprise.getLedgerForAuth(c.get("auth"));
    return c.json({ ledger });
  });

  /** Debit-on-store gate for callers outside createThread (tests / future L2 paths). */
  routes.post("/billing/debit", authMiddleware(store), async (c) => {
    const body = await c.req.json<{
      listing_id?: string;
      address?: string;
      thread_id: string;
      payload_bytes?: number;
      estimated_tokens?: number;
      blob_count?: number;
      latency_ms?: number;
    }>();
    const result = await store.enterprise.debitEnterpriseOnStore(c.get("auth"), {
      listing_id: body.listing_id,
      address: body.address,
      thread_id: body.thread_id,
      payload_bytes: body.payload_bytes ?? 0,
      estimated_tokens: body.estimated_tokens,
      blob_count: body.blob_count,
      latency_ms: body.latency_ms,
    });
    return c.json(result);
  });

  routes.get("/listing/:idOrAddress", async (c) => {
    const raw = c.req.param("idOrAddress")!;
    return c.json(
      await store.enterprise.getListingPublic(decodeURIComponent(raw)),
    );
  });

  return routes;
}
