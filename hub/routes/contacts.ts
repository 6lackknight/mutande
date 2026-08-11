import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";

export function createContactRoutes(store: HubStore) {
  const contactRoutes = new Hono<HubEnv>();
  contactRoutes.use("*", authMiddleware(store));

  /** Same-org contacts + broadcast. */
  contactRoutes.get("/", async (c) => {
    const result = await store.listContacts(c.get("auth"));
    return c.json(result);
  });

  /** Approved cross-org external contacts (§6.2). */
  contactRoutes.get("/external", async (c) => {
    return c.json(await store.listExternalContacts(c.get("auth")));
  });

  contactRoutes.delete("/external/:linkId", async (c) => {
    const result = await store.unpairExternalContact(
      c.get("auth"),
      c.req.param("linkId"),
    );
    return c.json(result);
  });

  /** Alice: issue / read / rotate pairing PIN (§6.3). */
  contactRoutes.post("/pairing/pin", async (c) => {
    return c.json(await store.issuePairingPin(c.get("auth")), 201);
  });

  contactRoutes.get("/pairing/pin", async (c) => {
    const pin = await store.getPairingPin(c.get("auth"));
    return c.json({ pin });
  });

  contactRoutes.post("/pairing/pin/rotate", async (c) => {
    return c.json(await store.rotatePairingPin(c.get("auth")));
  });

  /** Bob: submit exact handle + PIN. */
  contactRoutes.post("/pairing/request", async (c) => {
    const body = await c.req.json() as {
      handle?: unknown;
      pin?: unknown;
      intro?: unknown;
    };
    const result = await store.submitPairRequest(c.get("auth"), {
      handle: typeof body.handle === "string" ? body.handle : "",
      pin: typeof body.pin === "string" ? body.pin : "",
      ...(typeof body.intro === "string" ? { intro: body.intro } : {}),
    });
    return c.json(result, 201);
  });

  contactRoutes.get("/pairing/pending", async (c) => {
    return c.json(await store.listPendingPairRequests(c.get("auth")));
  });

  contactRoutes.post("/pairing/:requestId/approve", async (c) => {
    const result = await store.approvePairRequest(
      c.get("auth"),
      c.req.param("requestId"),
    );
    return c.json(result);
  });

  contactRoutes.post("/pairing/:requestId/deny", async (c) => {
    const result = await store.denyPairRequest(
      c.get("auth"),
      c.req.param("requestId"),
    );
    return c.json(result);
  });

  return contactRoutes;
}
