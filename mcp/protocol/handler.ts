import type { HubClient, HubClientError } from "../hub/client.ts";
import {
  closeThreadAsUser,
  deleteThreadAsUser,
  forwardDraftAsWebAgent,
  getWebAgentThread,
  listAgentsForUser,
  listContactsForUser,
  listWebAgentThreads,
  markProcessedHosted,
  replyAsWebAgent,
  upvoteMessageAsWebAgent,
} from "../hub/inbox.ts";
import type { ThreadFilter } from "../hub/types.ts";
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
  hub: HubClient;
}

export async function handleMcpRequest(
  req: McpRequest,
  ctx: HandlerContext,
): Promise<McpResponse | null> {
  // Notifications: no id / notifications/* → no response.
  if (req.method.startsWith("notifications/") || req.id === undefined || req.id === null) {
    return null;
  }

  const id = req.id;

  switch (req.method) {
    case "initialize":
      return mcpSuccess(id, {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: {
          name: "mutande-mcp",
          version: ctx.serverVersion,
        },
      });
    case "tools/list":
      return mcpSuccess(id, { tools: toolDefinitions() });
    case "tools/call": {
      const params = (req.params ?? {}) as {
        name?: string;
        arguments?: Record<string, unknown>;
      };
      const name = params.name?.trim();
      if (!name) {
        return mcpError(id, -32602, "tools/call requires params.name");
      }
      try {
        const result = await callTool(name, params.arguments ?? {}, ctx);
        return mcpSuccess(id, result);
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        const status =
          e && typeof e === "object" && "status" in e
            ? Number((e as HubClientError).status)
            : undefined;
        return mcpSuccess(
          id,
          toolTextResult(
            status ? `hub error (${status}): ${message}` : message,
            true,
          ),
        );
      }
    }
    case "ping":
      return mcpSuccess(id, {});
    default:
      return mcpError(id, -32601, `method not found: ${req.method}`);
  }
}

function requireString(args: Record<string, unknown>, key: string): string {
  const v = args[key];
  return typeof v === "string" ? v.trim() : "";
}

function requireBundle(
  args: Record<string, unknown>,
): Record<string, unknown> | null {
  if (args.bundle && typeof args.bundle === "object" && !Array.isArray(args.bundle)) {
    return args.bundle as Record<string, unknown>;
  }
  return null;
}

async function callTool(
  name: string,
  args: Record<string, unknown>,
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

  if (name === "list_threads") {
    const filterRaw = typeof args.filter === "string" ? args.filter : undefined;
    const filter = filterRaw as ThreadFilter | undefined;
    const { threads, caught_up } = await listWebAgentThreads(
      ctx.hub,
      ctx.session.accessToken,
      ctx.session.agent.id,
      filter,
    );
    // Skill pattern: empty / caught up → quiet payload.
    if (caught_up) {
      return toolTextResult(
        JSON.stringify({
          threads: [],
          caught_up: true,
          agent_id: ctx.session.agent.id,
          message: "caught up — no action needed",
        }),
      );
    }
    return toolTextResult(
      JSON.stringify(
        {
          threads,
          caught_up: false,
          agent_id: ctx.session.agent.id,
        },
        null,
        2,
      ),
    );
  }

  if (name === "get_thread") {
    const threadId = requireString(args, "thread_id");
    if (!threadId) {
      return toolTextResult("thread_id is required", true);
    }
    const detail = await getWebAgentThread(
      ctx.hub,
      ctx.session.accessToken,
      ctx.session.agent.id,
      threadId,
    );
    return toolTextResult(JSON.stringify(detail, null, 2));
  }

  if (name === "reply_to_thread") {
    const threadId = requireString(args, "thread_id");
    const bundle = requireBundle(args);
    if (!threadId) {
      return toolTextResult("thread_id is required", true);
    }
    if (!bundle) {
      return toolTextResult("bundle object is required", true);
    }
    const result = await replyAsWebAgent(
      ctx.hub,
      ctx.session.accessToken,
      ctx.session.agent.id,
      ctx.session.slug,
      threadId,
      bundle,
    );
    return toolTextResult(JSON.stringify({ ok: true, ...result }, null, 2));
  }

  if (name === "list_agents") {
    const handle = requireString(args, "handle") || undefined;
    const result = await listAgentsForUser(
      ctx.hub,
      ctx.session.accessToken,
      handle,
    );
    return toolTextResult(JSON.stringify(result, null, 2));
  }

  if (name === "list_contacts") {
    const result = await listContactsForUser(
      ctx.hub,
      ctx.session.accessToken,
    );
    return toolTextResult(JSON.stringify(result, null, 2));
  }

  if (name === "forward_draft") {
    const recipient =
      requireString(args, "recipient") || requireString(args, "to");
    const bundle = requireBundle(args) ?? {};
    if (!recipient) {
      return toolTextResult("recipient is required", true);
    }
    // Ephemeral draft: require some readable content for a useful handoff.
    const hasContent = Boolean(
      (typeof bundle.notes === "string" && bundle.notes.trim()) ||
        (typeof bundle.subject === "string" && bundle.subject.trim()) ||
        (typeof bundle.context === "string" && bundle.context.trim()) ||
        (Array.isArray(bundle.questions) && bundle.questions.length > 0) ||
        (Array.isArray(bundle.resources) && bundle.resources.length > 0) ||
        (Array.isArray(bundle.resource_requests) &&
          bundle.resource_requests.length > 0),
    );
    if (!hasContent) {
      return toolTextResult(
        "bundle must include notes, subject, context, questions, and/or resources",
        true,
      );
    }
    const result = await forwardDraftAsWebAgent(
      ctx.hub,
      ctx.session.accessToken,
      ctx.session.slug,
      recipient,
      bundle,
    );
    return toolTextResult(
      JSON.stringify(
        {
          ok: true,
          thread_id: result.thread.id,
          message_id: result.message_id,
          encryption_mode: result.thread.encryption_mode ?? "app_envelope",
          thread: result.thread,
        },
        null,
        2,
      ),
    );
  }

  if (name === "close_thread") {
    const threadId = requireString(args, "thread_id");
    if (!threadId) {
      return toolTextResult("thread_id is required", true);
    }
    const result = await closeThreadAsUser(
      ctx.hub,
      ctx.session.accessToken,
      threadId,
    );
    return toolTextResult(
      JSON.stringify({ ok: true, thread: result.thread }, null, 2),
    );
  }

  if (name === "delete_thread") {
    const threadId = requireString(args, "thread_id");
    if (!threadId) {
      return toolTextResult("thread_id is required", true);
    }
    await deleteThreadAsUser(ctx.hub, ctx.session.accessToken, threadId);
    return toolTextResult(JSON.stringify({ ok: true, thread_id: threadId }));
  }

  if (name === "upvote_message") {
    const threadId = requireString(args, "thread_id");
    const messageId = requireString(args, "message_id");
    if (!threadId) {
      return toolTextResult("thread_id is required", true);
    }
    if (!messageId) {
      return toolTextResult("message_id is required", true);
    }
    const result = await upvoteMessageAsWebAgent(
      ctx.hub,
      ctx.session.accessToken,
      ctx.session.slug,
      threadId,
      messageId,
    );
    return toolTextResult(JSON.stringify({ ok: true, ...result }, null, 2));
  }

  if (name === "mark_processed") {
    const threadId = requireString(args, "thread_id");
    if (!threadId) {
      return toolTextResult("thread_id is required", true);
    }
    return toolTextResult(
      JSON.stringify(markProcessedHosted(threadId), null, 2),
    );
  }

  if (!IMPLEMENTED_TOOLS.has(name)) {
    const known = toolDefinitions().some((t) => t.name === name);
    return toolTextResult(
      known
        ? `not implemented: tool "${name}" on hosted MCP. Use the mutande Mac sidecar MCP for E2E mail and remaining tools.`
        : `unknown tool: ${name}`,
      true,
    );
  }

  return toolTextResult(`unknown tool: ${name}`, true);
}
