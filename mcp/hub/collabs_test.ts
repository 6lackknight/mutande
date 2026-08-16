import { assertEquals } from "jsr:@std/assert@1";
import { presentCollab } from "./collabs.ts";
import type { CollabView } from "./types.ts";

function sample(partial: Partial<CollabView> = {}): CollabView {
  return {
    id: "c-berry",
    name: "BerrySure",
    encryption_mode: "app_envelope",
    instructions: "Ship the alpha.",
    lists: [{ id: "backlog", name: "Backlog", position: 0 }],
    card_count: 1,
    memory_thread_id: "mem-1",
    steerers: [{ user_id: "u1", handle: "Alice@Acme" }],
    roster: [{ address: "Alice@Acme/ChatGPT", transport: "mcp" }],
    cards: [{
      id: "t-card",
      last_subject: "Landing copy",
      lane_id: "backlog",
      status: "open",
      from: "Alice@Acme",
      audience: "Alice@Acme/chatgpt",
    }],
    artifacts: [
      { kind: "link", label: "Staging", url: "https://staging.example.com" },
      { kind: "file", name: "brief.md", content: "hello", envelope: { version: 1 } },
    ],
    learnings: [{
      id: "l1",
      created_at: "2026-08-16T00:00:00Z",
      from_handle: "Alice@Acme",
      notes: "Prefer bronze.",
    }],
    ...partial,
  } as CollabView;
}

Deno.test("presentCollab is participant-complete and lowercases handles", () => {
  const view = presentCollab(sample());
  assertEquals(view.id, "c-berry");
  assertEquals(view.name, "BerrySure");
  assertEquals(view.instructions, "Ship the alpha.");
  assertEquals((view.people as Array<{ handle: string }>)[0].handle, "alice@acme");
  assertEquals(
    (view.agents as Array<{ address: string }>)[0].address,
    "alice@acme/chatgpt",
  );
  const cards = view.cards as Array<{ thread_id: string; subject?: string }>;
  assertEquals(cards[0].thread_id, "t-card");
  assertEquals(cards[0].subject, "Landing copy");
  const arts = view.artifacts as Array<{ kind: string; url?: string; envelope?: unknown }>;
  assertEquals(arts[0].kind, "link");
  assertEquals(arts[0].url, "https://staging.example.com");
  assertEquals(arts[1].kind, "file");
  assertEquals(arts[1].envelope, undefined);
  assertEquals(view.org_id, undefined);
  assertEquals(view.steerers, undefined);
  assertEquals(view.status, "open");
});

Deno.test("hosted E2E get_collab strips sealed file payloads", () => {
  const view = presentCollab(
    sample({ encryption_mode: "e2e" }),
    { hosted: true },
  );
  assertEquals(view.sidecar_required, true);
  const arts = view.artifacts as Array<{ kind: string; content?: string }>;
  assertEquals(arts[1].content, undefined);
});

Deno.test("presentCollab includes archived status", () => {
  const view = presentCollab(sample({ status: "archived" }));
  assertEquals(view.status, "archived");
});
