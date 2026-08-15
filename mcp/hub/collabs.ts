/** Hosted MCP collab helpers — app_envelope boards only. */

import { HubClient, HubClientError } from "./client.ts";
import type { CollabView } from "./types.ts";

const E2E_COLLAB_REFUSAL =
  "This collab is E2E — use the mutande Mac sidecar MCP. Hosted MCP cannot seal cards or the brain.";

export function assertAppEnvelopeCollab(collab: CollabView): void {
  if (collab.encryption_mode === "e2e") {
    throw new Error(E2E_COLLAB_REFUSAL);
  }
}

export async function listCollabsAsUser(
  hub: HubClient,
  accessToken: string,
): Promise<{ collabs: CollabView[] }> {
  const { collabs } = await hub.listCollabs(accessToken);
  return { collabs };
}

export async function getCollabAsUser(
  hub: HubClient,
  accessToken: string,
  collabId: string,
): Promise<CollabView> {
  const { collab } = await hub.getCollab(accessToken, collabId);
  return collab;
}

export async function setLaneAsUser(
  hub: HubClient,
  accessToken: string,
  collabId: string,
  input: {
    thread_id: string;
    lane_id: string;
    before_thread_id?: string;
    after_thread_id?: string;
  },
): Promise<{ thread: unknown }> {
  return hub.setLane(accessToken, collabId, input);
}

export async function addLearningAsWebAgent(
  hub: HubClient,
  accessToken: string,
  collabId: string,
  notes: string,
  slug: string,
  agentId: string,
): Promise<{ message_id: string }> {
  const { collab } = await hub.getCollab(accessToken, collabId);
  assertAppEnvelopeCollab(collab);
  try {
    return await hub.addLearning(accessToken, collabId, {
      notes,
      from_agent: slug,
      from_agent_id: agentId,
    });
  } catch (e) {
    if (e instanceof HubClientError && e.status === 403) {
      throw new Error(
        e.message || "Only the collab creator's side may add_learning",
      );
    }
    throw e;
  }
}

export { E2E_COLLAB_REFUSAL };
