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
        "UTF-8 text for .md/.txt/.json. Prefer this. Never base64 text. Never /mnt/data paths.",
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
      "Attachments with INLINE bytes. Text: {name, content}. Binary: {name, content_base64, mime}. Never path-only /mnt/data.",
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
        "List app_envelope threads for this web agent. Each item includes thread_id, title/subject (message subject or notes peek; else address fallback), from/to + participants[] (agent slugs e.g. chatgpt→cursor), status, your_status, reply_count, created_at/updated_at, encryption_mode. Default filter=needs_action (inbox to do). Use filter=open for outbound you sent (needs_action hides those — your_status is replied). caught_up=true when empty — stay quiet for needs_action. Read-only.",
      inputSchema: {
        type: "object",
        properties: {
          filter: {
            type: "string",
            enum: ["needs_action", "open", "closed"],
            description:
              "needs_action (default) = inbox to do. open = including outbound you started. closed = archived.",
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
      name: "reply_to_thread",
      description:
        "Reply on an app_envelope thread. Put body in bundle.notes (UTF-8). Attachments: resources[].content for text; content_base64 only for binary. Never /mnt/data paths.",
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
        "Start an app_envelope thread (not E2E). No local draft store. You may pass subject/notes/resources at the top level OR inside bundle (same shape as desktop drafts). Body: notes UTF-8. Text files: resources[{name, content}] — never /mnt/data, never base64 text. Binary pdf/png: content_base64+mime (~1MB). Self: @all/@claude/@cursor/@chatgpt. Teammates: alice@org, alice@org/claude, @all@org. Success JSON always includes thread_id, message_id, resource_count, resource_names.",
      inputSchema: {
        type: "object",
        required: ["recipient"],
        properties: {
          recipient: {
            type: "string",
            description:
              "Self: @all or @claude/@cursor/@chatgpt. Teammates: alice@org, alice@org/claude, @all@org.",
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
