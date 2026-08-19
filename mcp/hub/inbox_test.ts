import { assertEquals } from "jsr:@std/assert@1";
import {
  applyAppEnvelopeSnippets,
  bundleToAppEnvelope,
  E2E_REFUSAL,
  filterThreadsForWebAgent,
  isE2eWireError,
  markProcessedHosted,
  mapHubSendError,
  participantLabel,
  presentThreadForWeb,
  presentThreadListItem,
  threadForWebAgent,
  threadListTitle,
  threadParticipants,
} from "./inbox.ts";
import type { ThreadDetail, ThreadMeta } from "./types.ts";

function baseMeta(partial: Partial<ThreadMeta> & Pick<ThreadMeta, "id">): ThreadMeta {
  return {
    kind: "direct",
    status: "open",
    from: "u@acme/chatgpt",
    from_user_id: "u",
    audience: "u@acme/cursor",
    org_id: "o",
    participant_count: 2,
    reply_count: 1,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-02T00:00:00.000Z",
    encryption_mode: "app_envelope",
    your_status: "pending",
    ...partial,
  };
}

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

Deno.test("threadForWebAgent matches dual-slot audience slug", () => {
  const thread = baseMeta({
    id: "t-dual",
    audience: "u@acme/chatgpt",
    audience_agent_id: "sidecar-chatgpt",
    encryption_mode: "app_envelope",
  });
  assertEquals(threadForWebAgent(thread, "web-chatgpt"), false);
  assertEquals(threadForWebAgent(thread, "web-chatgpt", "chatgpt"), true);
  assertEquals(threadForWebAgent(thread, "web-chatgpt", "claude"), false);
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

Deno.test("participantLabel prefers agent slug", () => {
  assertEquals(participantLabel("u@acme/chatgpt"), "chatgpt");
  assertEquals(participantLabel("u@acme/cursor"), "cursor");
  assertEquals(participantLabel("@all"), "@all");
  assertEquals(participantLabel("alice@acme"), "alice@acme");
});

Deno.test("presentThreadListItem includes subject + participants", () => {
  const item = presentThreadListItem(
    baseMeta({
      id: "t1",
      last_subject: "Need review",
      last_preview: "please look at the PR",
      reply_count: 2,
    }),
  );
  assertEquals(item.thread_id, "t1");
  assertEquals(item.id, "t1");
  assertEquals(item.subject, "Need review");
  assertEquals(item.title, "Need review");
  assertEquals(item.from, "u@acme/chatgpt");
  assertEquals(item.to, "u@acme/cursor");
  assertEquals(item.participants, ["chatgpt", "cursor"]);
  assertEquals(item.preview, "please look at the PR");
  assertEquals(item.status, "open");
  assertEquals(item.your_status, "pending");
  assertEquals(item.reply_count, 2);
  assertEquals(item.encryption_mode, "app_envelope");
});

Deno.test("threadListTitle falls back like Mac UI", () => {
  assertEquals(
    threadListTitle(baseMeta({ id: "a", last_subject: "  Subj  " })),
    "Subj",
  );
  assertEquals(
    threadListTitle(baseMeta({ id: "b", audience: "@all", last_subject: undefined })),
    "@all",
  );
  assertEquals(
    threadListTitle(
      baseMeta({
        id: "c",
        from: "u@acme/chatgpt",
        audience: "u@acme/cursor",
        last_subject: undefined,
      }),
    ),
    "u@acme/cursor",
  );
  assertEquals(threadParticipants(baseMeta({ id: "d" })), ["chatgpt", "cursor"]);
});

Deno.test("applyAppEnvelopeSnippets peeks subject and notes", () => {
  const thread = baseMeta({ id: "t-peek" });
  const detail: ThreadDetail = {
    thread,
    messages: [
      {
        id: "m1",
        thread_id: "t-peek",
        from_user_id: "u",
        from_handle: "u@acme/chatgpt",
        created_at: "2026-01-01T00:00:00.000Z",
        app_envelope: {
          version: 1,
          subject: "Kickoff",
          notes: "start here",
        },
      },
      {
        id: "m2",
        thread_id: "t-peek",
        from_user_id: "u",
        from_handle: "u@acme/cursor",
        parent_message_id: "m1",
        created_at: "2026-01-02T00:00:00.000Z",
        app_envelope: {
          version: 1,
          notes: "reply body without subject",
        },
      },
    ],
  };
  const enriched = applyAppEnvelopeSnippets(thread, detail);
  assertEquals(enriched.last_from, "u@acme/cursor");
  // Latest has no subject → fall back to OP subject.
  assertEquals(enriched.last_subject, "Kickoff");
  assertEquals(enriched.last_preview, "reply body without subject");
  const item = presentThreadListItem(enriched);
  assertEquals(item.title, "Kickoff");
  assertEquals(item.participants, ["chatgpt", "cursor"]);
});
