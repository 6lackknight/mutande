/** Thin HTTP client for hub APIs used by the hosted MCP service. */

import type {
  AgentsListResponse,
  AppEnvelopePayload,
  CloseThreadResponse,
  Contact,
  CreateThreadResponse,
  DeleteThreadResponse,
  HubAgentRow,
  ReplyResponse,
  ThreadDetail,
  ThreadFilter,
  ThreadMeta,
  ToggleUpvoteResponse,
} from "./types.ts";

export interface HubMeResponse {
  auth0_sub: string;
  email?: string;
  onboarded?: boolean;
  needs_onboarding?: boolean;
  user?: { id: string; handle?: string; org_id?: string };
  org?: { id: string; slug: string };
}

export type HubAgent = HubAgentRow;

export class HubClientError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly body?: unknown,
  ) {
    super(message);
    this.name = "HubClientError";
  }
}

export class HubClient {
  constructor(private readonly hubUrl: string) {}

  private async request<T>(
    path: string,
    accessToken: string,
    init?: RequestInit,
  ): Promise<T> {
    const res = await fetch(`${this.hubUrl}${path}`, {
      ...init,
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/json",
        "Content-Type": "application/json",
        ...(init?.headers ?? {}),
      },
    });
    const text = await res.text();
    let body: unknown = undefined;
    if (text) {
      try {
        body = JSON.parse(text);
      } catch {
        body = text;
      }
    }
    if (!res.ok) {
      const msg =
        typeof body === "object" && body && "message" in body
          ? String((body as { message: unknown }).message)
          : `hub ${path} failed (${res.status})`;
      throw new HubClientError(msg, res.status, body);
    }
    return body as T;
  }

  getMe(accessToken: string): Promise<HubMeResponse> {
    return this.request<HubMeResponse>("/v1/me", accessToken);
  }

  /**
   * Capability handshake for hosted MCP — hub assigns transport=mcp.
   * Body may only include client-declared fields (slug + optional capabilities).
   */
  connectMcpAgent(
    accessToken: string,
    input: {
      slug: string;
      models?: string[];
      default_model?: string;
      modalities?: string[];
      message_types?: string[];
    },
  ): Promise<{ agent: HubAgent }> {
    return this.request<{ agent: HubAgent }>("/v1/agents/connect/mcp", accessToken, {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  /** List inbox threads (user-scoped). Hosted MCP filters to the bound web agent. */
  listThreads(
    accessToken: string,
    filter?: ThreadFilter,
  ): Promise<{ threads: ThreadMeta[] }> {
    const q = filter ? `?filter=${encodeURIComponent(filter)}` : "";
    return this.request<{ threads: ThreadMeta[] }>(`/v1/threads${q}`, accessToken);
  }

  getThread(accessToken: string, threadId: string): Promise<ThreadDetail> {
    return this.request<ThreadDetail>(
      `/v1/threads/${encodeURIComponent(threadId)}`,
      accessToken,
    );
  }

  /**
   * App-envelope-only fetch for web/MCP pull.
   * Prefer this over getThread when the agent only handles non-E2E mail.
   */
  fetchAppMessages(
    accessToken: string,
    threadId: string,
    agentId?: string,
  ): Promise<ThreadDetail> {
    const q = agentId ? `?agent_id=${encodeURIComponent(agentId)}` : "";
    return this.request<ThreadDetail>(
      `/v1/threads/${encodeURIComponent(threadId)}/app-messages${q}`,
      accessToken,
    );
  }

  createThread(
    accessToken: string,
    input: {
      to: string;
      app_envelope: AppEnvelopePayload;
      from_agent?: string;
    },
  ): Promise<CreateThreadResponse> {
    return this.request<CreateThreadResponse>("/v1/threads", accessToken, {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  replyToThread(
    accessToken: string,
    threadId: string,
    input: {
      app_envelope: AppEnvelopePayload;
      from_agent?: string;
      to_agent?: string;
      parent_message_id?: string;
    },
  ): Promise<ReplyResponse> {
    return this.request<ReplyResponse>(
      `/v1/threads/${encodeURIComponent(threadId)}/replies`,
      accessToken,
      {
        method: "POST",
        body: JSON.stringify(input),
      },
    );
  }

  /** Bound Auth0 user agents (dual sidecar/mcp slots when present). */
  listAgents(
    accessToken: string,
    handle?: string,
  ): Promise<AgentsListResponse> {
    const q = handle
      ? `?handle=${encodeURIComponent(handle.trim())}`
      : "";
    return this.request<AgentsListResponse>(`/v1/agents${q}`, accessToken);
  }

  /** Same-org contacts + @all@org broadcast (desktop list_contacts). */
  listContacts(accessToken: string): Promise<{ contacts: Contact[] }> {
    return this.request<{ contacts: Contact[] }>("/v1/contacts", accessToken);
  }

  /** Approved cross-org external contacts (L3). */
  listExternalContacts(
    accessToken: string,
  ): Promise<{ contacts: Contact[] }> {
    return this.request<{ contacts: Contact[] }>(
      "/v1/contacts/external",
      accessToken,
    );
  }

  closeThread(
    accessToken: string,
    threadId: string,
  ): Promise<CloseThreadResponse> {
    return this.request<CloseThreadResponse>(
      `/v1/threads/${encodeURIComponent(threadId)}/close`,
      accessToken,
      { method: "POST", body: "{}" },
    );
  }

  deleteThread(
    accessToken: string,
    threadId: string,
  ): Promise<DeleteThreadResponse> {
    return this.request<DeleteThreadResponse>(
      `/v1/threads/${encodeURIComponent(threadId)}`,
      accessToken,
      { method: "DELETE" },
    );
  }

  upvoteMessage(
    accessToken: string,
    threadId: string,
    messageId: string,
    fromAgent?: string,
  ): Promise<ToggleUpvoteResponse> {
    return this.request<ToggleUpvoteResponse>(
      `/v1/threads/${encodeURIComponent(threadId)}/messages/${
        encodeURIComponent(messageId)
      }/upvote`,
      accessToken,
      {
        method: "POST",
        body: JSON.stringify(
          fromAgent ? { from_agent: fromAgent } : {},
        ),
      },
    );
  }
}
