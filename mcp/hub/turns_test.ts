import { assertEquals } from "jsr:@std/assert@1";
import {
  deriveNextTurn,
  foldAwaiting,
  hubTurnsMirror,
  inferIntent,
  mergeReply,
} from "./turns.ts";

Deno.test("inferIntent defaults handoff", () => {
  assertEquals(inferIntent({ notes: "hi" }), "handoff");
  assertEquals(inferIntent({ intent: "answer", notes: "ok" }), "answer");
});

Deno.test("derive handoff targets recipient agent", () => {
  const next = deriveNextTurn(
    "handoff",
    { notes: "go" },
    [],
    "alice@acme/chatgpt",
    "@cursor",
    "alice@acme",
  );
  assertEquals(next, [{
    address: "@cursor",
    actor: "agent",
    reason: { kind: "handoff" },
  }]);
});

Deno.test("derive fyi is empty", () => {
  assertEquals(
    deriveNextTurn("fyi", { notes: "n" }, [], "a@x/c", "b@x/d", "a@x"),
    [],
  );
});

Deno.test("merge clears replier and unions declarations", () => {
  const next = mergeReply(
    [
      { address: "alice@acme/chatgpt", actor: "agent", reason: { kind: "handoff" } },
      { address: "alice@acme/cursor", actor: "agent", reason: { kind: "handoff" } },
    ],
    "alice@acme/chatgpt",
    [{ address: "alice@acme/cursor", actor: "agent", reason: { kind: "handoff" } }],
    [],
  );
  assertEquals(next.length, 1);
  assertEquals(next[0].address, "alice@acme/cursor");
});

Deno.test("fold starts from first declared next_turn", () => {
  const awaiting = foldAwaiting([
    {
      from_handle: "alice@acme/chatgpt",
      app_envelope: {
        intent: "handoff",
        next_turn: [{ address: "@cursor", actor: "agent", reason: { kind: "handoff" } }],
      },
    },
    {
      from_handle: "alice@acme/cursor",
      app_envelope: { intent: "answer", next_turn: [] },
    },
  ]);
  assertEquals(awaiting, []);
});

Deno.test("hubTurnsMirror prefers human actor", () => {
  const mirrored = hubTurnsMirror(
    [
      { address: "bob@acme/claude", actor: "agent" },
      { address: "bob@acme", actor: "human" },
    ],
    (bare) => bare === "bob@acme" ? "u-bob" : undefined,
  );
  assertEquals(mirrored, [{ user_id: "u-bob", actor: "human" }]);
});
