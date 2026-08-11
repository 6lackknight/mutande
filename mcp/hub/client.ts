/** Thin HTTP client for hub APIs used by the hosted MCP service. */

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
}
