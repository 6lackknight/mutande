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
import {
  addLearningAsWebAgent,
  getCollabAsUser,
  listCollabsAsUser,
  setLaneAsUser,
  createCardAsUser,
} from "../hub/collabs.ts";
import type { ThreadFilter } from "../hub/types.ts";
import type { McpSession } from "../session/bind.ts";
import { captureMcpException } from "../sentry.ts";
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
          "When the user names a project/board, list_collabs then get_collab (do not only search list_threads subjects). " +
          "Add work on a named collab with create_card(title, collab_id, lane) — don't start an unfiled thread. " +
          "Send with forward_draft(recipient, …). You may pass subject/notes/resources at the top level OR inside bundle (same shape as desktop drafts). " +
          "Text body → notes (UTF-8). Attachments: resources[{name, content}] UTF-8 — that IS the named file in the thread (Mac shows a file chip; not a stub). NEVER /mnt/data paths, NEVER base64 text. " +
          "Binary pdf/png only → resources[{name, content_base64, mime}], keep under ~1MB. " +
          "On success report thread_id, message_id, attachments[{name,bytes}], resource_count, resource_names. " +
          "When asked to /handshake or introduce yourself, call publish_handshake (thread_id if on a thread). Names only — never tokens or paths.",
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
        captureMcpException(e);
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

function handshakeNotes(card: Record<string, unknown>): string {
  const lines = ["Handshake"];
  const str = (k: string) =>
    typeof card[k] === "string" && String(card[k]).trim()
      ? String(card[k]).trim()
      : "";
  const list = (k: string) =>
    Array.isArray(card[k])
      ? (card[k] as unknown[]).filter((x) => typeof x === "string" && String(x).trim()).join(", ")
      : "";
  if (str("host")) lines.push(`Host: ${str("host")}`);
  if (str("address")) lines.push(`Address: ${str("address")}`);
  if (list("models")) lines.push(`Models: ${list("models")}`);
  if (list("skills")) lines.push(`Skills: ${list("skills")}`);
  if (list("ask_me_about")) lines.push(`Ask me about: ${list("ask_me_about")}`);
  if (str("preferred_file_format")) {
    lines.push(`Preferred files: ${str("preferred_file_format")}`);
  }
  if (list("other_tools")) lines.push(`Other tools: ${list("other_tools")}`);
  return lines.join("\n");
}

function requireBundle(
  args: Record<string, unknown>,
): Record<string, unknown> | null {
  if (args.bundle && typeof args.bundle === "object" && !Array.isArray(args.bundle)) {
    return args.bundle as Record<string, unknown>;
  }
  return null;
}

/** Bundle field keys hosts may pass flat or nested (desktop draft shape). */
const BUNDLE_FIELD_KEYS = [
  "subject",
  "notes",
  "context",
  "questions",
  "answers",
  "resources",
  "resource_requests",
  "in_reply_to",
  "ping_kind",
  "version",
] as const;

/**
 * Accept flat top-level subject/notes/resources OR nested `bundle: { … }`.
 * Prefer explicit top-level when both are present; otherwise unwrap bundle.
 * (Models often copy desktop draft shape; ChatGPT may mix flat + nested.)
 */
export function normalizeForwardDraftBundle(
  args: Record<string, unknown>,
): Record<string, unknown> {
  const nested = requireBundle(args);
  const out: Record<string, unknown> = nested ? { ...nested } : {};
  for (const key of BUNDLE_FIELD_KEYS) {
    if (!(key in args) || args[key] === undefined) continue;
    // Top-level wins when both present.
    out[key] = args[key];
  }
  return out;
}

/** Named file attachments that carried inline payload (for forward_draft success). */
function summarizeInlineResources(bundle: Record<string, unknown>): {
  resource_count: number;
  resource_names: string[];
  attachments: Array<{ name: string; bytes: number }>;
} {
  const resources = Array.isArray(bundle.resources) ? bundle.resources : [];
  const resource_names: string[] = [];
  const attachments: Array<{ name: string; bytes: number }> = [];
  for (const r of resources) {
    if (!r || typeof r !== "object") continue;
    const o = r as Record<string, unknown>;
    const content = typeof o.content === "string" ? o.content : "";
    const b64 = typeof o.content_base64 === "string" ? o.content_base64 : "";
    const data = typeof o.data === "string" ? o.data : "";
    const body = typeof o.body === "string" ? o.body : "";
    const inline = Boolean(
      content.trim() || b64.trim() || data.trim() || body.trim(),
    );
    if (!inline) continue;
    const name = typeof o.name === "string" && o.name.trim()
      ? o.name.trim()
      : "(unnamed)";
    resource_names.push(name);
    let bytes = 0;
    if (content.trim()) {
      bytes = new TextEncoder().encode(content).length;
    } else if (b64.trim()) {
      // Approximate decoded size from base64 length.
      const cleaned = b64.replace(/\s+/g, "");
      bytes = Math.floor(cleaned.length * 0.75);
    } else if (data.trim()) {
      bytes = new TextEncoder().encode(data).length;
    } else if (body.trim()) {
      bytes = new TextEncoder().encode(body).length;
    }
    attachments.push({ name, bytes });
  }
  return {
    resource_count: resource_names.length,
    resource_names,
    attachments,
  };
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
      typeof args.collab_id === "string" ? args.collab_id : undefined,
      ctx.session.slug,
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
      ctx.session.slug,
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

  if (name === "list_collabs") {
    const result = await listCollabsAsUser(ctx.hub, ctx.session.accessToken);
    return toolTextResult(JSON.stringify(result, null, 2));
  }

  if (name === "get_collab") {
    const collabId = requireString(args, "collab_id");
    if (!collabId) {
      return toolTextResult("collab_id is required", true);
    }
    const collab = await getCollabAsUser(
      ctx.hub,
      ctx.session.accessToken,
      collabId,
    );
    return toolTextResult(JSON.stringify({ collab }, null, 2));
  }

  if (name === "create_card") {
    const collabId = requireString(args, "collab_id");
    const title =
      requireString(args, "title") || requireString(args, "subject");
    const lane =
      requireString(args, "lane") || requireString(args, "lane_id") || undefined;
    const notes = requireString(args, "notes") || undefined;
    const assignedTo = requireString(args, "assigned_to") || undefined;
    const dueOn = requireString(args, "due_on") || undefined;
    const tags = Array.isArray(args.tags)
      ? args.tags.filter((t): t is string => typeof t === "string")
      : undefined;
    const checklist = Array.isArray(args.checklist)
      ? args.checklist
      : undefined;
    if (!collabId || !title) {
      return toolTextResult("collab_id and title are required", true);
    }
    const handle = (ctx.session.me.user?.handle ?? "").trim().toLowerCase();
    if (!handle) {
      return toolTextResult("signed-in handle is required", true);
    }
    const result = await createCardAsUser(
      ctx.hub,
      ctx.session.accessToken,
      {
        collab_id: collabId,
        title,
        lane,
        notes,
        assigned_to: assignedTo,
        tags,
        due_on: dueOn,
        checklist: checklist as
          | { id?: string; text: string; done?: boolean }[]
          | undefined,
      },
      {
        handle,
        slug: ctx.session.slug,
        agentId: ctx.session.agent.id,
      },
    );
    return toolTextResult(JSON.stringify(result, null, 2));
  }

  if (name === "set_lane") {
    const collabId = requireString(args, "collab_id");
    const threadId = requireString(args, "thread_id");
    const laneId = requireString(args, "lane_id");
    if (!collabId || !threadId || !laneId) {
      return toolTextResult("collab_id, thread_id, and lane_id are required", true);
    }
    const result = await setLaneAsUser(
      ctx.hub,
      ctx.session.accessToken,
      collabId,
      {
        thread_id: threadId,
        lane_id: laneId,
        before_thread_id: requireString(args, "before_thread_id") || undefined,
        after_thread_id: requireString(args, "after_thread_id") || undefined,
      },
    );
    return toolTextResult(JSON.stringify(result, null, 2));
  }

  if (name === "add_learning") {
    const collabId = requireString(args, "collab_id");
    const notes = requireString(args, "notes");
    if (!collabId || !notes) {
      return toolTextResult("collab_id and notes are required", true);
    }
    try {
      const result = await addLearningAsWebAgent(
        ctx.hub,
        ctx.session.accessToken,
        collabId,
        notes,
        ctx.session.slug,
        ctx.session.agent.id,
      );
      return toolTextResult(JSON.stringify(result, null, 2));
    } catch (e) {
      captureMcpException(e);
      return toolTextResult(
        e instanceof Error ? e.message : "add_learning failed",
        true,
      );
    }
  }

  if (name === "forward_draft") {
    const recipient =
      requireString(args, "recipient") || requireString(args, "to");
    const bundle = normalizeForwardDraftBundle(args);
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
        "Pass notes, subject, context, questions, and/or resources with inline content at the top level or inside bundle (not host paths like /mnt/data/…)",
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
      requireString(args, "collab_id") || undefined,
    );
    const threadId = result.thread?.id;
    const messageId = result.message_id;
    if (!threadId || !messageId) {
      return toolTextResult(
        "forward_draft failed: hub returned no thread_id/message_id",
        true,
      );
    }
    const { resource_count, resource_names, attachments } =
      summarizeInlineResources(bundle);
    return toolTextResult(
      JSON.stringify(
        {
          ok: true,
          thread_id: threadId,
          message_id: messageId,
          // Named files landed in the thread (resources[].content IS the attachment).
          attachments,
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

  if (name === "publish_handshake") {
    const nested =
      args.handshake && typeof args.handshake === "object" &&
        !Array.isArray(args.handshake)
        ? args.handshake as Record<string, unknown>
        : {};
    const pick = (key: string): unknown =>
      args[key] !== undefined ? args[key] : nested[key];
    const slug = ctx.session.slug;
    const handle = ctx.session.me.user?.handle;
    const hostGuess = slug.toLowerCase().includes("chatgpt")
      ? "ChatGPT"
      : slug.toLowerCase().includes("claude")
      ? "Claude"
      : slug.toLowerCase().includes("cursor")
      ? "Cursor"
      : "AI host";
    const card: Record<string, unknown> = {
      host: pick("host") ?? hostGuess,
      address: pick("address") ??
        (handle ? `${handle}/${slug}` : undefined),
      models: pick("models"),
      skills: pick("skills"),
      ask_me_about: pick("ask_me_about"),
      preferred_file_format: pick("preferred_file_format"),
      other_tools: pick("other_tools"),
    };
    const stored = await ctx.hub.putAgentHandshake(
      ctx.session.accessToken,
      ctx.session.agent.id,
      card,
    );
    const handshake = stored.handshake ?? card;
    const notes = handshakeNotes(handshake);
    const bundle: Record<string, unknown> = {
      subject: "Handshake",
      notes,
      handshake,
    };
    const threadId = requireString(args, "thread_id");
    const recipient = requireString(args, "recipient") ||
      requireString(args, "to");
    let mailed: { thread_id?: string; message_id?: string } = {};
    if (threadId) {
      const result = await replyAsWebAgent(
        ctx.hub,
        ctx.session.accessToken,
        ctx.session.agent.id,
        ctx.session.slug,
        threadId,
        bundle,
      );
      mailed = { thread_id: threadId, message_id: result.message_id };
    } else if (recipient) {
      const result = await forwardDraftAsWebAgent(
        ctx.hub,
        ctx.session.accessToken,
        ctx.session.agent.id,
        ctx.session.slug,
        recipient,
        bundle,
        undefined,
      );
      mailed = {
        thread_id: result.thread?.id,
        message_id: result.message_id,
      };
    }
    return toolTextResult(
      JSON.stringify({ ok: true, handshake, ...mailed }, null, 2),
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
