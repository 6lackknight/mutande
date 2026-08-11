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
          title: "mutande",
          version: ctx.serverVersion,
          description:
            "Agent-to-agent encrypted mail for teams — threads, handoffs, and inbox tools over Auth0.",
          websiteUrl: "https://mutande.online/docs/hosted-mcp",
          icons: [
            {
              src: "https://mutande.online/brand/icon-192.png",
              mimeType: "image/png",
              sizes: ["192x192"],
            },
            {
              src: "https://mutande.online/brand/favicon-32.png",
              mimeType: "image/png",
              sizes: ["32x32"],
            },
          ],
        },
        instructions:
          "mutande = agent collaboration mail (handoffs, threads, @all). app_envelope only — not E2E (Mac sidecar for E2E). " +
          "New chat: list_threads (default needs_action); stay quiet if caught_up. Outbound you sent: filter=open. " +
          "Send with forward_draft(recipient, bundle). Text body → bundle.notes (UTF-8). " +
          "Attachments: .md/.txt → resources[{name, content}] UTF-8 string — NEVER /mnt/data paths, NEVER base64 text. " +
          "Binary pdf/png only → resources[{name, content_base64, mime}], keep under ~1MB. " +
          "On success report thread_id, message_id, resource_count, resource_names.",
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

/** Names of resources that carried inline payload (for forward_draft success). */
function summarizeInlineResources(bundle: Record<string, unknown>): {
  resource_count: number;
  resource_names: string[];
} {
  const resources = Array.isArray(bundle.resources) ? bundle.resources : [];
  const resource_names: string[] = [];
  for (const r of resources) {
    if (!r || typeof r !== "object") continue;
    const o = r as Record<string, unknown>;
    const inline = Boolean(
      (typeof o.content === "string" && o.content.trim()) ||
        (typeof o.content_base64 === "string" && o.content_base64.trim()) ||
        (typeof o.data === "string" && o.data.trim()) ||
        (typeof o.body === "string" && o.body.trim()),
    );
    if (!inline) continue;
    const name = typeof o.name === "string" && o.name.trim()
      ? o.name.trim()
      : "(unnamed)";
    resource_names.push(name);
  }
  return { resource_count: resource_names.length, resource_names };
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
    // needs_action omits threads you already sent (your_status=replied) —
    // use filter=open to see outbound app_envelope mail you created.
    if (caught_up) {
      return toolTextResult(
        JSON.stringify({
          threads: [],
          caught_up: true,
          agent_id: ctx.session.agent.id,
          filter: filter ?? "needs_action",
          message:
            filter === "open" || filter === "closed"
              ? "no matching app_envelope threads"
              : "caught up — no action needed (use filter=open to see threads you started)",
        }),
      );
    }
    return toolTextResult(
      JSON.stringify(
        {
          threads,
          caught_up: false,
          agent_id: ctx.session.agent.id,
          filter: filter ?? "needs_action",
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
    // Path-only resources do not count — hosted MCP cannot read /mnt/data/….
    const resources = Array.isArray(bundle.resources) ? bundle.resources : [];
    const hasInlineResource = resources.some((r) => {
      if (!r || typeof r !== "object") return false;
      const o = r as Record<string, unknown>;
      return Boolean(
        (typeof o.content === "string" && o.content.trim()) ||
          (typeof o.content_base64 === "string" && o.content_base64.trim()) ||
          (typeof o.data === "string" && o.data.trim()) ||
          (typeof o.body === "string" && o.body.trim()),
      );
    });
    const hasContent = Boolean(
      (typeof bundle.notes === "string" && bundle.notes.trim()) ||
        (typeof bundle.subject === "string" && bundle.subject.trim()) ||
        (typeof bundle.context === "string" && bundle.context.trim()) ||
        (Array.isArray(bundle.questions) && bundle.questions.length > 0) ||
        hasInlineResource ||
        (Array.isArray(bundle.resource_requests) &&
          bundle.resource_requests.length > 0),
    );
    if (!hasContent) {
      return toolTextResult(
        "bundle must include notes, subject, context, questions, and/or resources with inline content (not host paths like /mnt/data/…)",
        true,
      );
    }
    const result = await forwardDraftAsWebAgent(
      ctx.hub,
      ctx.session.accessToken,
      ctx.session.agent.id,
      ctx.session.slug,
      recipient,
      bundle,
    );
    const threadId = result.thread?.id;
    const messageId = result.message_id;
    if (!threadId || !messageId) {
      return toolTextResult(
        "forward_draft failed: hub returned no thread_id/message_id",
        true,
      );
    }
    const { resource_count, resource_names } = summarizeInlineResources(bundle);
    return toolTextResult(
      JSON.stringify(
        {
          ok: true,
          thread_id: threadId,
          message_id: messageId,
          resource_count,
          resource_names,
          encryption_mode: result.thread.encryption_mode ?? "app_envelope",
          recipient,
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
      ctx.session.agent.id,
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
