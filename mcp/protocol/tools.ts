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

/** L0 + L2 inbox tools. */
export const IMPLEMENTED_TOOLS = new Set([
  "health",
  "ping",
  "list_threads",
  "get_thread",
  "reply_to_thread",
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
      description: "List your agent slugs. STUB on hosted MCP until later wiring.",
      inputSchema: {
        type: "object",
        properties: { handle: { type: "string" } },
        additionalProperties: false,
      },
    },
    {
      name: "list_contacts",
      description: "List org contacts. STUB on hosted MCP until later wiring.",
      inputSchema: { ...EMPTY_OBJECT },
    },
    {
      name: "forward_draft",
      description:
        "Send a draft. STUB on hosted MCP — web agents reply via reply_to_thread; new threads from desktop sidecar.",
      inputSchema: {
        type: "object",
        properties: {
          to: { type: "string" },
          bundle: { type: "object" },
        },
        additionalProperties: false,
      },
    },
  ];
}
