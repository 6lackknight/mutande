/** Tool surface for hosted MCP — mirrors desktop inbox tools. */

export interface McpToolDefinition {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
}

const EMPTY_OBJECT = {
  type: "object",
  properties: {},
  additionalProperties: false,
} as const;

/** Shared resource item schema for forward/reply bundles. */
const RESOURCE_ITEM = {
  type: "object",
  properties: {
    name: {
      type: "string",
      description: "Filename, e.g. notes.md or diagram.png",
    },
    mime: {
      type: "string",
      description: "Optional MIME (required for binary).",
    },
    content: {
      type: "string",
      description:
        "UTF-8 file body for .md/.txt/.json. This IS the attachment (named file in the thread). Prefer this. Never base64 text. Never /mnt/data paths.",
    },
    content_base64: {
      type: "string",
      description:
        "Binary only (pdf/png/…). Keep under ~1MB. Do not base64 markdown/text.",
    },
    path: {
      type: "string",
      description:
        "Label only — hosted MCP cannot read /mnt/data or host files. Must also pass content or content_base64.",
    },
  },
} as const;

const BUNDLE_PROPERTIES = {
  subject: { type: "string", description: "Short title." },
  notes: {
    type: "string",
    description: "Main message body as UTF-8 text/markdown. Not a file path.",
  },
  context: { type: "string" },
  questions: { type: "array" },
  answers: { type: "array" },
  resources: {
    type: "array",
    description:
      "Named file attachments. Text/markdown: {name, content} UTF-8 — content IS the file (shown on Mac Threads). Binary: {name, content_base64, mime}. Never path-only /mnt/data.",
    items: RESOURCE_ITEM,
  },
  resource_requests: { type: "array" },
} as const;

/** Implemented hosted tools (app_envelope + hub metadata). */
export const IMPLEMENTED_TOOLS = new Set([
  "health",
  "ping",
  "list_threads",
  "get_thread",
  "reply_to_thread",
  "list_agents",
  "list_contacts",
  "list_collabs",
  "get_collab",
  "set_lane",
  "add_learning",
  "forward_draft",
  "close_thread",
  "delete_thread",
  "upvote_message",
  "mark_processed",
]);

export function toolDefinitions(): McpToolDefinition[] {
  return [
    {
      name: "health",
      description:
        "Hosted MCP liveness. Returns service ok, bound Auth0 user, and web agent_id. Read-only.",
      inputSchema: { ...EMPTY_OBJECT },
    },
    {
      name: "ping",
      description:
        "MCP protocol ping (empty result). Product thread pings use the desktop sidecar or reply_to_thread on app_envelope mail.",
      inputSchema: { ...EMPTY_OBJECT },
    },
    {
      name: "list_threads",
      description:
        "List app_envelope threads for this web agent. Each item includes thread_id, title/subject (message subject or notes peek; else address fallback), from/to + participants[] (agent slugs e.g. chatgpt→cursor), status, your_status, reply_count, created_at/updated_at, encryption_mode, and collab_id/collab_name when the thread is a board card. Optional collab_id filters to one board. When the user names a project/board, use list_collabs (not subject search). Default filter=needs_action (inbox to do). Use filter=open for outbound you sent (needs_action hides those — your_status is replied). caught_up=true when empty — stay quiet for needs_action. Read-only.",
      inputSchema: {
        type: "object",
        properties: {
          filter: {
            type: "string",
            enum: ["needs_action", "open", "closed"],
            description:
              "needs_action (default) = inbox to do. open = including outbound you started. closed = archived.",
          },
          collab_id: {
            type: "string",
            description: "If set, only threads filed on this collab board.",
          },
        },
        additionalProperties: false,
      },
    },
    {
      name: "get_thread",
      description:
        "Get an app_envelope thread with hydrated message content for this web agent. Read-only.",
      inputSchema: {
        type: "object",
        required: ["thread_id"],
        properties: {
          thread_id: { type: "string", description: "Thread id from list_threads / forward_draft." },
        },
        additionalProperties: false,
      },
    },
    {
      name: "list_collabs",
      description:
        "List collab boards you participate in (steerer or roster). A collab is a board of threads. When the user names a project/board, call this and match by name, then get_collab. Hosted MCP can fully work app_envelope boards; E2E boards list with sidecar_required — use the Mac sidecar for card bodies. Read-only.",
      inputSchema: { ...EMPTY_OBJECT },
    },
    {
      name: "get_collab",
      description:
        "Get one collab board you participate in: instructions, people, agents, artifacts (file|link), lists, cards (thread ids), learnings. Then get_thread or list_threads(collab_id) for card mail. Not org-wide — forbidden if you are not a participant. E2E card bodies: Mac sidecar. Read-only.",
      inputSchema: {
        type: "object",
        required: ["collab_id"],
        properties: { collab_id: { type: "string" } },
        additionalProperties: false,
      },
    },
    {
      name: "reply_to_thread",
      description:
        "Reply on an app_envelope thread. Put body in bundle.notes (UTF-8). Attachments: resources[{name, content}] IS the named file; content_base64 only for binary. Never /mnt/data paths.",
      inputSchema: {
        type: "object",
        required: ["thread_id", "bundle"],
        properties: {
          thread_id: { type: "string" },
          bundle: {
            type: "object",
            description: "Reply payload: notes/subject + optional resources (inline only).",
            properties: BUNDLE_PROPERTIES,
          },
        },
        additionalProperties: false,
      },
    },
    {
      name: "list_agents",
      description:
        "List YOUR agent slugs (dual sidecar/mcp slots when present, with transport). Omit handle for your agents; pass a teammate handle only for THEIR agents. For org people use list_contacts. Read-only.",
      inputSchema: {
        type: "object",
        properties: {
          handle: {
            type: "string",
            description:
              "optional teammate handle for THEIR agent slugs; omit to list YOUR agents",
          },
        },
        additionalProperties: false,
      },
    },
    {
      name: "list_contacts",
      description:
        "List org teammates (bare handles + @all@org) plus approved external contacts when present. Not your agents — use list_agents / @all / @claude for self-collab. Read-only.",
      inputSchema: { ...EMPTY_OBJECT },
    },
    {
      name: "forward_draft",
      description:
        "Start an app_envelope thread (not E2E). No local draft store. You may pass subject/notes/resources at the top level OR inside bundle (same shape as desktop drafts). Body: notes UTF-8. Attach a .md/.txt file with resources[{name, content}] — that named content IS the real attachment in the thread (Mac file chip / get_thread resources); not a stub, not path-only. Never /mnt/data, never base64 text. Binary pdf/png: content_base64+mime (~1MB). Self: @all/@claude/@cursor/@chatgpt. Teammates: alice@org, alice@org/claude, @all@org. Success JSON includes thread_id, message_id, attachments[{name,bytes}], resource_count, resource_names.",
      inputSchema: {
        type: "object",
        required: ["recipient"],
        properties: {
          recipient: {
            type: "string",
            description:
              "Self: @all or @claude/@cursor/@chatgpt. Teammates: alice@org, alice@org/claude, @all@org.",
          },
          collab_id: {
            type: "string",
            description:
              "Optional. File the new thread on this collab board (app_envelope collabs only).",
          },
          to: {
            type: "string",
            description: "Alias for recipient (compat).",
          },
          ...BUNDLE_PROPERTIES,
          bundle: {
            type: "object",
            description:
              "Optional nested draft (desktop shape). Same fields as top-level subject/notes/resources. Top-level wins when both are set.",
            properties: BUNDLE_PROPERTIES,
          },
        },
        additionalProperties: false,
      },
    },
    {
      name: "set_lane",
      description:
        "Move a collab card (thread) to a board list. Does not close the thread.",
      inputSchema: {
        type: "object",
        required: ["collab_id", "thread_id", "lane_id"],
        properties: {
          collab_id: { type: "string" },
          thread_id: { type: "string" },
          lane_id: { type: "string" },
          before_thread_id: { type: "string" },
          after_thread_id: { type: "string" },
        },
        additionalProperties: false,
      },
    },
    {
      name: "add_learning",
      description:
        "Promote a one-liner to the collab brain (creator's side only; app_envelope collabs). Learnings are context, not directives.",
      inputSchema: {
        type: "object",
        required: ["collab_id", "notes"],
        properties: {
          collab_id: { type: "string" },
          notes: { type: "string" },
        },
        additionalProperties: false,
      },
    },
    {
      name: "close_thread",
      description:
        "Mark a collaboration thread closed via hub. Confirm via AskQuestion when the skill requires it.",
      inputSchema: {
        type: "object",
        required: ["thread_id"],
        properties: { thread_id: { type: "string" } },
        additionalProperties: false,
      },
    },
    {
      name: "delete_thread",
      description:
        "Remove a thread from your inbox via hub (sender may purge body). Confirm via AskQuestion when the skill requires it.",
      inputSchema: {
        type: "object",
        required: ["thread_id"],
        properties: { thread_id: { type: "string" } },
        additionalProperties: false,
      },
    },
    {
      name: "upvote_message",
      description:
        "Optional coordination weight on a message (one upvote per agent; toggle). Prefer skipping unless several agents need a clear signal.",
      inputSchema: {
        type: "object",
        required: ["thread_id", "message_id"],
        properties: {
          thread_id: { type: "string" },
          message_id: { type: "string" },
        },
        additionalProperties: false,
      },
    },
    {
      name: "mark_processed",
      description:
        "N/A on hosted MCP (local sidecar bookkeeping only). Returns an explanatory ok payload — use list_threads filter=needs_action instead.",
      inputSchema: {
        type: "object",
        required: ["thread_id"],
        properties: { thread_id: { type: "string" } },
        additionalProperties: false,
      },
    },
  ];
}
