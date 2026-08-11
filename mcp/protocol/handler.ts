import type { McpSession } from "../session/bind.ts";
import { toolDefinitions, IMPLEMENTED_TOOLS } from "./tools.ts";
import {
  mcpError,
  mcpSuccess,
  toolTextResult,
  type McpRequest,
  type McpResponse,
} from "./types.ts";

export interface HandlerContext {
  session: McpSession;
  serverVersion: string;
}

export function handleMcpRequest(
  req: McpRequest,
  ctx: HandlerContext,
): Promise<McpResponse | null> {
  // Notifications: no id / notifications/* → no response.
  if (req.method.startsWith("notifications/") || req.id === undefined || req.id === null) {
    return Promise.resolve(null);
  }

  const id = req.id;

  switch (req.method) {
    case "initialize":
      return Promise.resolve(mcpSuccess(id, {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: {
          name: "mutande-mcp",
          version: ctx.serverVersion,
        },
      }));
    case "tools/list":
      return Promise.resolve(mcpSuccess(id, { tools: toolDefinitions() }));
    case "tools/call": {
      const params = (req.params ?? {}) as {
        name?: string;
        arguments?: Record<string, unknown>;
      };
      const name = params.name?.trim();
      if (!name) {
        return Promise.resolve(
          mcpError(id, -32602, "tools/call requires params.name"),
        );
      }
      return Promise.resolve(
        mcpSuccess(id, callTool(name, params.arguments ?? {}, ctx)),
      );
    }
    case "ping":
      return Promise.resolve(mcpSuccess(id, {}));
    default:
      return Promise.resolve(
        mcpError(id, -32601, `method not found: ${req.method}`),
      );
  }
}

function callTool(
  name: string,
  _args: Record<string, unknown>,
  ctx: HandlerContext,
) {
  if (name === "health") {
    const { session } = ctx;
    return toolTextResult(
      JSON.stringify(
        {
          ok: true,
          service: "mutande-mcp",
          version: ctx.serverVersion,
          auth0_sub: session.claims.sub,
          handle: session.me.user?.handle ?? null,
          agent_id: session.agent.id,
          slug: session.slug,
          transport: session.agent.transport ?? "mcp",
          bound_at: session.boundAt,
        },
        null,
        2,
      ),
    );
  }

  if (name === "ping") {
    return toolTextResult(JSON.stringify({ ok: true }));
  }

  if (!IMPLEMENTED_TOOLS.has(name)) {
    const known = toolDefinitions().some((t) => t.name === name);
    return toolTextResult(
      known
        ? `not implemented: tool "${name}" on hosted MCP (L0 scaffold). Inbox tools ship with L2 app_envelope pull. Use the mutande Mac sidecar MCP for E2E mail today.`
        : `unknown tool: ${name}`,
      true,
    );
  }

  return toolTextResult(`unknown tool: ${name}`, true);
}
