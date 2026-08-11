/** Tool surface for hosted MCP — mirrors desktop inbox tools; most are stubs until L2. */

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

/** Implemented in L0. */
export const IMPLEMENTED_TOOLS = new Set(["health", "ping"]);

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
        "MCP protocol ping (empty result). For a product thread ping, use the desktop sidecar until L2 wires hub app_envelope tools.",
      inputSchema: { ...EMPTY_OBJECT },
    },
    // --- Stubs: same names as local MCP; return not-implemented until L2 ---
    {
      name: "list_threads",
      description:
        "List collaboration threads. STUB on hosted MCP until L2 (app_envelope pull).",
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
        "Get a thread. STUB on hosted MCP until L2 (app_envelope pull).",
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
        "Reply to a thread. STUB on hosted MCP until L2 (app_envelope).",
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
      description: "List your agent slugs. STUB on hosted MCP until L1/L2 wiring.",
      inputSchema: {
        type: "object",
        properties: { handle: { type: "string" } },
        additionalProperties: false,
      },
    },
    {
      name: "list_contacts",
      description: "List org contacts. STUB on hosted MCP until L2.",
      inputSchema: { ...EMPTY_OBJECT },
    },
    {
      name: "forward_draft",
      description: "Send a draft. STUB on hosted MCP until L2.",
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
