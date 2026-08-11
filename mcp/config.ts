/** Runtime config for the hosted MCP service (env overrides). */

function trimSlash(url: string): string {
  return url.replace(/\/+$/, "");
}

export interface McpConfig {
  /** Canonical public URL, e.g. https://mcp.mutande.online */
  publicUrl: string;
  auth0Domain: string;
  /** Primary access-token audience (hub API by default). */
  auth0Audience: string;
  /** Optional extra audience (MCP resource indicator). */
  auth0McpAudience: string | null;
  issuerAliases: string[];
  hubUrl: string;
  defaultAgentSlug: string;
  port: number;
}

export function loadConfig(env: {
  get(key: string): string | undefined;
} = Deno.env): McpConfig {
  const publicUrl = trimSlash(
    env.get("MCP_PUBLIC_URL")?.trim() || "https://mcp.mutande.online",
  );
  const auth0Domain = (env.get("AUTH0_DOMAIN")?.trim() || "auth.mutande.online")
    .replace(/^https?:\/\//, "")
    .replace(/\/+$/, "");
  const auth0Audience =
    env.get("AUTH0_AUDIENCE")?.trim() || "https://hub.mutande.app";
  const mcpAud = env.get("AUTH0_MCP_AUDIENCE")?.trim() || null;
  const aliases = (env.get("AUTH0_ISSUER_ALIASES") ?? "")
    .split(",")
    .map((h) => h.trim())
    .filter(Boolean);
  const hubUrl = trimSlash(
    env.get("MUTANDE_HUB_URL")?.trim() || "https://hub.mutande.online",
  );
  const defaultAgentSlug =
    (env.get("MCP_DEFAULT_AGENT_SLUG")?.trim() || "chatgpt").toLowerCase();
  const port = Number(env.get("PORT") || "3849") || 3849;

  return {
    publicUrl,
    auth0Domain,
    auth0Audience,
    auth0McpAudience: mcpAud && mcpAud !== auth0Audience ? mcpAud : null,
    issuerAliases: aliases,
    hubUrl,
    defaultAgentSlug,
    port,
  };
}

export function requireAuth0OnDeploy(config: McpConfig): void {
  if (!Deno.env.get("DENO_DEPLOYMENT_ID")) return;
  if (!config.auth0Domain || !config.auth0Audience) {
    throw new Error(
      "AUTH0_DOMAIN and AUTH0_AUDIENCE are required on Deno Deploy",
    );
  }
}
