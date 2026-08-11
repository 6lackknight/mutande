import type { Auth0Claims } from "../auth/oauth.ts";
import type { HubAgent, HubClient, HubMeResponse } from "../hub/client.ts";

/** Bound MCP session after Auth0 login + hub connect/mcp upsert. */
export interface McpSession {
  accessToken: string;
  claims: Auth0Claims;
  me: HubMeResponse;
  agent: HubAgent;
  slug: string;
  boundAt: string;
}

/**
 * Bind an Auth0 access token to a mutande MCP agent slot via POST /v1/agents/connect/mcp.
 * Requires the user to already be onboarded on the hub (create/join org on Mac or web).
 */
export async function bindWebSession(
  hub: HubClient,
  accessToken: string,
  claims: Auth0Claims,
  slug: string,
): Promise<McpSession> {
  const me = await hub.getMe(accessToken);
  if (me.needs_onboarding || me.onboarded === false) {
    throw new Error(
      "Onboarding required: create or join a team in the mutande Mac app or at mutande.online before connecting the web MCP connector.",
    );
  }

  const { agent } = await hub.connectMcpAgent(accessToken, {
    slug: slug.trim().toLowerCase(),
  });

  return {
    accessToken,
    claims,
    me,
    agent,
    slug: agent.slug,
    boundAt: new Date().toISOString(),
  };
}
