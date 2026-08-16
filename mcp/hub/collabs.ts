/** Hosted MCP collab helpers — app_envelope boards only for writes; list/get for participants. */

import { HubClient, HubClientError } from "./client.ts";
import type { CollabView } from "./types.ts";

const E2E_COLLAB_REFUSAL =
  "This collab is E2E — use the mutande Mac sidecar MCP. Hosted MCP cannot seal cards or the brain.";

export function assertAppEnvelopeCollab(collab: CollabView): void {
  if (collab.encryption_mode === "e2e") {
    throw new Error(E2E_COLLAB_REFUSAL);
  }
}

function lower(s: string): string {
  return s.trim().toLowerCase();
}

function asRecord(v: unknown): Record<string, unknown> {
  return v && typeof v === "object" && !Array.isArray(v)
    ? v as Record<string, unknown>
    : {};
}

function str(v: unknown): string {
  return typeof v === "string" ? v : "";
}

function optStr(v: unknown): string | undefined {
  const s = typeof v === "string" ? v.trim() : "";
  return s ? s : undefined;
}

/** Agent-facing board object: people, agents, artifacts, related cards. No hub URLs, no envelopes. */
export function presentCollab(
  raw: CollabView,
  opts?: { hosted?: boolean },
): Record<string, unknown> {
  const rec = asRecord(raw);
  const e2e = str(raw.encryption_mode) === "e2e";
  const hosted = opts?.hosted === true;
  const sidecarRequired = hosted && e2e;

  const people = Array.isArray(rec.steerers)
    ? (rec.steerers as unknown[]).flatMap((s) => {
      const handle = optStr(asRecord(s).handle);
      return handle ? [{ handle: lower(handle) }] : [];
    })
    : [];
  const agents = Array.isArray(rec.roster)
    ? (rec.roster as unknown[]).flatMap((r) => {
      const row = asRecord(r);
      const address = optStr(row.address);
      if (!address) return [];
      const out: Record<string, unknown> = { address: lower(address) };
      if (optStr(row.transport)) out.transport = row.transport;
      return [out];
    })
    : [];

  const cards = Array.isArray(rec.cards)
    ? (rec.cards as unknown[]).flatMap((c) => {
      const row = asRecord(c);
      const id = optStr(row.id);
      if (!id) return [];
      return [{
        thread_id: id,
        id,
        subject: optStr(row.last_subject) ?? optStr(row.subject),
        lane_id: optStr(row.lane_id),
        lane_position: row.lane_position,
        status: optStr(row.status),
        assigned_to: optStr(row.assigned_to)
          ? lower(String(row.assigned_to))
          : undefined,
        from: optStr(row.from) ? lower(String(row.from)) : undefined,
        audience: optStr(row.audience) ? lower(String(row.audience)) : undefined,
        your_status: optStr(row.your_status),
        updated_at: optStr(row.updated_at),
      }];
    })
    : [];

  const artifacts = Array.isArray(rec.artifacts)
    ? (rec.artifacts as unknown[]).map((a) => {
      const row = asRecord(a);
      const kind = optStr(row.kind)?.toLowerCase() === "link" ? "link" : "file";
      const out: Record<string, unknown> = {
        kind,
        label: optStr(row.label),
        name: optStr(row.name),
        mime: optStr(row.mime),
        size: row.size,
        thread_id: optStr(row.thread_id),
        card_title: optStr(row.card_title),
      };
      if (kind === "link") {
        out.url = optStr(row.url);
      } else if (!sidecarRequired) {
        const path = optStr(row.path);
        if (path) out.path = path;
        else if (optStr(row.content)) out.content = row.content;
      }
      return out;
    })
    : [];

  const learnings = Array.isArray(rec.learnings)
    ? (rec.learnings as unknown[]).map((l) => {
      const row = asRecord(l);
      const sealed = row.sealed === true;
      return {
        id: optStr(row.id),
        created_at: optStr(row.created_at) ?? optStr(row.at),
        from_handle: optStr(row.from_handle)
          ? lower(String(row.from_handle))
          : undefined,
        notes: sidecarRequired && sealed ? undefined : optStr(row.notes),
        sealed: row.sealed,
      };
    })
    : [];

  const view: Record<string, unknown> = {
    id: str(raw.id),
    name: str(raw.name),
    instructions: sidecarRequired ? undefined : optStr(raw.instructions),
    encryption_mode: optStr(raw.encryption_mode),
    people,
    agents,
    lists: rec.lists ?? [],
    cards,
    artifacts,
    learnings,
    card_count: typeof rec.card_count === "number" ? rec.card_count : cards.length,
    memory_thread_id: optStr(rec.memory_thread_id),
  };
  if (sidecarRequired) {
    view.sidecar_required = true;
    view.note =
      "E2E collab — card bodies and file artifacts open on the Mac sidecar MCP.";
  }
  return view;
}

export async function listCollabsAsUser(
  hub: HubClient,
  accessToken: string,
): Promise<{ collabs: Record<string, unknown>[] }> {
  const { collabs } = await hub.listCollabs(accessToken);
  return {
    collabs: (collabs ?? []).map((c) => presentCollab(c, { hosted: true })),
  };
}

export async function getCollabAsUser(
  hub: HubClient,
  accessToken: string,
  collabId: string,
): Promise<Record<string, unknown>> {
  try {
    const { collab } = await hub.getCollab(accessToken, collabId);
    return presentCollab(collab, { hosted: true });
  } catch (e) {
    if (e instanceof HubClientError && (e.status === 403 || e.status === 404)) {
      throw e;
    }
    throw e;
  }
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

export async function createCardAsUser(
  hub: HubClient,
  accessToken: string,
  input: {
    collab_id: string;
    title: string;
    lane?: string;
    notes?: string;
  },
  from: { handle: string; slug: string; agentId: string },
): Promise<{
  ok: true;
  thread_id: string;
  collab_id: string;
  lane_id?: string;
}> {
  const { collab } = await hub.getCollab(accessToken, input.collab_id);
  assertAppEnvelopeCollab(collab);
  const to = from.handle.trim().toLowerCase();
  const title = input.title.trim();
  if (!title) {
    throw new Error("title is required");
  }
  const notes = input.notes?.trim();
  const result = await hub.createThread(accessToken, {
    to,
    app_envelope: {
      version: 1,
      subject: title,
      ...(notes ? { notes } : {}),
    },
    from_agent: from.slug,
    from_agent_id: from.agentId,
    collab_id: input.collab_id,
    ...(input.lane ? { lane_id: input.lane } : {}),
  });
  const threadId = result?.thread?.id?.trim();
  if (!threadId) {
    throw new Error("create_card failed: hub returned no thread_id");
  }
  return {
    ok: true,
    thread_id: threadId,
    collab_id: input.collab_id,
    lane_id: result.thread.lane_id,
  };
}
