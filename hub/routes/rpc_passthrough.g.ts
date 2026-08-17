// GENERATED FILE — do not edit. Source: proto/rpc-catalog.json (deno task generate in proto/).
import { Hono } from "hono";
import { authMiddleware, type HubEnv } from "../middleware/auth.ts";
import type { HubStore } from "../store/store.ts";

/** Mechanical hub forwards declared in proto/rpc-catalog.json. */
export function createPassthroughRoutes(store: HubStore) {
  const routes = new Hono<HubEnv>();
  const auth = authMiddleware(store);

  // list_external_contacts
  routes.get("/v1/contacts/external", auth, async (c) => {
    const result = await store.listExternalContacts(c.get("auth"));
    return c.json(result);
  });

  // get_registry_listing
  routes.get("/v1/registry/listing/:id_or_address", async (c) => {
    const result = await store.enterprise.getListingPublic(decodeURIComponent(c.req.param("id_or_address")!));
    return c.json(result);
  });

  // issue_pairing_pin
  routes.post("/v1/contacts/pairing/pin", auth, async (c) => {
    const result = await store.issuePairingPin(c.get("auth"));
    return c.json(result, 201);
  });

  // get_pairing_pin
  routes.get("/v1/contacts/pairing/pin", auth, async (c) => {
    const result = await store.getPairingPin(c.get("auth"));
    return c.json({ pin: result });
  });

  // rotate_pairing_pin
  routes.post("/v1/contacts/pairing/pin/rotate", auth, async (c) => {
    const result = await store.rotatePairingPin(c.get("auth"));
    return c.json(result);
  });

  // submit_pair_request
  routes.post("/v1/contacts/pairing/request", auth, async (c) => {
    const body = await c.req.json();
    const result = await store.submitPairRequest(c.get("auth"), body);
    return c.json(result, 201);
  });

  // list_pending_pair_requests
  routes.get("/v1/contacts/pairing/pending", auth, async (c) => {
    const result = await store.listPendingPairRequests(c.get("auth"));
    return c.json(result);
  });

  // approve_pair_request
  routes.post("/v1/contacts/pairing/:request_id/approve", auth, async (c) => {
    const result = await store.approvePairRequest(c.get("auth"), decodeURIComponent(c.req.param("request_id")!));
    return c.json(result);
  });

  // deny_pair_request
  routes.post("/v1/contacts/pairing/:request_id/deny", auth, async (c) => {
    const result = await store.denyPairRequest(c.get("auth"), decodeURIComponent(c.req.param("request_id")!));
    return c.json(result);
  });

  // unpair_external_contact
  routes.delete("/v1/contacts/external/:link_id", auth, async (c) => {
    const result = await store.unpairExternalContact(c.get("auth"), decodeURIComponent(c.req.param("link_id")!));
    return c.json(result);
  });

  // propose_thread_downgrade
  routes.post("/v1/threads/:thread_id/downgrade-proposals", auth, async (c) => {
    const body = await c.req.json();
    const result = await store.proposeThreadDowngrade(c.get("auth"), decodeURIComponent(c.req.param("thread_id")!), body);
    return c.json(result, 201);
  });

  // list_pending_thread_downgrades
  routes.get("/v1/threads/downgrade-proposals/pending", auth, async (c) => {
    const result = await store.listPendingThreadDowngrades(c.get("auth"));
    return c.json(result);
  });

  // deny_thread_downgrade
  routes.post("/v1/threads/:thread_id/downgrade-proposals/:proposal_id/deny", auth, async (c) => {
    const result = await store.denyThreadDowngrade(c.get("auth"), decodeURIComponent(c.req.param("thread_id")!), decodeURIComponent(c.req.param("proposal_id")!));
    return c.json(result);
  });

  // list_collabs
  routes.get("/v1/collabs", auth, async (c) => {
    const result = await store.listCollabs(c.get("auth"), { archived: c.req.query("archived") === "1" || c.req.query("archived") === "true" });
    return c.json(result);
  });

  // add_collab_steerer
  routes.post("/v1/collabs/:collab_id/steerers", auth, async (c) => {
    const body = await c.req.json();
    const result = await store.addCollabSteerer(c.get("auth"), decodeURIComponent(c.req.param("collab_id")!), body);
    return c.json({ collab: result });
  });

  // remove_collab_steerer
  routes.post("/v1/collabs/:collab_id/steerers/remove", auth, async (c) => {
    const body = await c.req.json();
    const result = await store.removeCollabSteerer(c.get("auth"), decodeURIComponent(c.req.param("collab_id")!), body);
    return c.json({ collab: result });
  });

  // add_collab_roster
  routes.post("/v1/collabs/:collab_id/roster", auth, async (c) => {
    const body = await c.req.json();
    const result = await store.addCollabRoster(c.get("auth"), decodeURIComponent(c.req.param("collab_id")!), body);
    return c.json({ collab: result });
  });

  // remove_collab_roster
  routes.post("/v1/collabs/:collab_id/roster/remove", auth, async (c) => {
    const body = await c.req.json();
    const result = await store.removeCollabRoster(c.get("auth"), decodeURIComponent(c.req.param("collab_id")!), body);
    return c.json({ collab: result });
  });

  // archive_collab
  routes.post("/v1/collabs/:collab_id/archive", auth, async (c) => {
    const result = await store.archiveCollab(c.get("auth"), decodeURIComponent(c.req.param("collab_id")!));
    return c.json({ collab: result });
  });

  // unarchive_collab
  routes.post("/v1/collabs/:collab_id/unarchive", auth, async (c) => {
    const result = await store.unarchiveCollab(c.get("auth"), decodeURIComponent(c.req.param("collab_id")!));
    return c.json({ collab: result });
  });

  // approve_collab_pending_membership
  routes.post("/v1/collabs/:collab_id/downgrade/approve", auth, async (c) => {
    const result = await store.approveCollabPendingMembership(c.get("auth"), decodeURIComponent(c.req.param("collab_id")!));
    return c.json({ collab: result });
  });

  // deny_collab_pending_membership
  routes.post("/v1/collabs/:collab_id/downgrade/deny", auth, async (c) => {
    const result = await store.denyCollabPendingMembership(c.get("auth"), decodeURIComponent(c.req.param("collab_id")!));
    return c.json({ collab: result });
  });

  // set_default_agent
  routes.put("/v1/agents/default", auth, async (c) => {
    const body = await c.req.json();
    const result = await store.setDefaultAgent(c.get("auth"), body);
    return c.json({ agent: result });
  });

  // rename_agent
  routes.patch("/v1/agents/:agent_id", auth, async (c) => {
    const body = await c.req.json();
    const result = await store.renameAgent(c.get("auth"), decodeURIComponent(c.req.param("agent_id")!), body);
    return c.json({ agent: result });
  });

  // get_router
  routes.get("/v1/agents/router", auth, async (c) => {
    const result = await store.getRouter(c.get("auth"));
    return c.json(result);
  });

  // set_router
  routes.put("/v1/agents/router", auth, async (c) => {
    const body = await c.req.json();
    const result = await store.setRouter(c.get("auth"), body);
    return c.json(result);
  });

  // get_transport_defaults
  routes.get("/v1/agents/transport-defaults", auth, async (c) => {
    const result = await store.getTransportPrefs(c.get("auth"));
    return c.json(result);
  });

  return routes;
}
