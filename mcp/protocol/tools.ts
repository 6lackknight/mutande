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
        "List app_envelope collaboration threads for this web agent. Default filter needs_action. Returns caught_up=true and an empty list when there is nothing to do — stay quiet (skill pattern). Read-only.",
      inputSchema: {
        type: "object",
        properties: {
          filter: {
            type: "string",
            enum: ["needs_action", "open", "closed"],
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
        properties: { thread_id: { type: "string" } },
        additionalProperties: false,
      },
    },
    {
      name: "reply_to_thread",
      description:
        "Reply on an app_envelope thread as this web agent. Bundle fields map to hub app_envelope (subject, notes, …).",
      inputSchema: {
        type: "object",
        required: ["thread_id", "bundle"],
        properties: {
          thread_id: { type: "string" },
          bundle: { type: "object" },
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
        "Start a new app_envelope collaboration thread (no local draft store — pass content in bundle). Self-collab: @all or @claude/@cursor/@chatgpt. Teammates: alice@org, alice@org/claude, @all@org. Never E2E — refused when the path would require sidecar seal.",
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
          bundle: {
            type: "object",
            description:
              "App envelope content: subject, notes, context, questions, resources, …",
            properties: {
              subject: { type: "string" },
              notes: { type: "string" },
              context: { type: "string" },
              questions: { type: "array" },
              answers: { type: "array" },
              resources: { type: "array" },
              resource_requests: { type: "array" },
            },
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
