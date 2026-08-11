import { assertEquals } from "jsr:@std/assert@1";
import {
  bundleToAppEnvelope,
  E2E_REFUSAL,
  filterThreadsForWebAgent,
  isE2eWireError,
  markProcessedHosted,
  mapHubSendError,
  presentThreadForWeb,
  threadForWebAgent,
} from "./inbox.ts";
import type { ThreadDetail, ThreadMeta } from "./types.ts";

Deno.test("bundleToAppEnvelope sets version 1", () => {
  const payload = bundleToAppEnvelope({ subject: "hi", notes: "n" });
  assertEquals(payload.version, 1);
  assertEquals(payload.subject, "hi");
});

Deno.test("presentThreadForWeb strips envelopes", () => {
  const detail: ThreadDetail = {
    thread: {
      id: "t",
      kind: "direct",
      status: "open",
      from: "a@acme/x",
      from_user_id: "a",
      audience: "b@acme/y",
      org_id: "o",
      participant_count: 2,
      reply_count: 0,
      created_at: "",
      updated_at: "",
      encryption_mode: "app_envelope",
      audience_agent_id: "web",
    },
    messages: [
      {
        id: "m",
        thread_id: "t",
        from_user_id: "a",
        from_handle: "a@acme/x",
        created_at: "",
        envelope: { version: 1 },
        app_envelope: { version: 1, notes: "hello" },
      },
    ],
  };
  const presented = presentThreadForWeb(detail);
  assertEquals(presented.messages[0].envelope, undefined);
  assertEquals(presented.messages[0].app_envelope?.notes, "hello");
});

Deno.test("filter empty when no matches", () => {
  const threads: ThreadMeta[] = [
    {
      id: "1",
      kind: "direct",
      status: "open",
      from: "a",
      from_user_id: "a",
      audience: "b",
      org_id: "o",
      participant_count: 2,
      reply_count: 0,
      created_at: "",
      updated_at: "",
      encryption_mode: "e2e",
    },
  ];
  assertEquals(filterThreadsForWebAgent(threads, "web").length, 0);
  assertEquals(threadForWebAgent(threads[0], "web"), false);
});

Deno.test("isE2eWireError detects hub E2E refusals", () => {
  assertEquals(
    isE2eWireError(new Error("E2E threads require envelope (not app_envelope)")),
    true,
  );
  assertEquals(isE2eWireError(new Error("something else")), false);
  assertEquals(mapHubSendError(new Error("E2E threads require envelope")).message, E2E_REFUSAL);
});

Deno.test("markProcessedHosted documents N/A", () => {
  const r = markProcessedHosted("t1");
  assertEquals(r.ok, true);
  assertEquals(r.na, true);
  assertEquals(r.thread_id, "t1");
});
