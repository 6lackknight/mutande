/** Thin HTTP client for hub APIs used by the hosted MCP service. */

import type {
  AppEnvelopePayload,
  CreateThreadResponse,
  ReplyResponse,
  ThreadDetail,
  ThreadFilter,
  ThreadMeta,
} from "./types.ts";

export interface HubMeResponse {
  auth0_sub: string;
  email?: string;
  onboarded?: boolean;
  needs_onboarding?: boolean;
  user?: { id: string; handle?: string; org_id?: string };
  org?: { id: string; slug: string };
}

export interface HubAgent {
  id: string;
  user_id: string;
  slug: string;
  created_at: string;
  transport?: string;
  mcp_endpoint?: string | null;
  [key: string]: unknown;
}

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
}
