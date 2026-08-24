import { assertValidAgentSlug } from "./address.ts";
import { conflict, forbidden, notFound } from "./errors.ts";
import { randomToken } from "./jwt.ts";

export const MCP_CONNECTOR_PREFIX = "mtc_";
export const MAX_MCP_CONNECTORS = 8;

export function isMcpConnectorToken(token: string): boolean {
  return (
    token.startsWith(MCP_CONNECTOR_PREFIX) &&
    token.length >= MCP_CONNECTOR_PREFIX.length + 16
  );
}

export interface McpConnectorRecord {
  id: string;
  user_id: string;
  token_hash: string;
  prefix: string;
  label: string;
  slug: string | null;
  created_at: string;
  last_used_at?: string;
  revoked_at?: string;
}

export interface McpConnectorView {
  id: string;
  prefix: string;
  label: string;
  slug: string | null;
  created_at: string;
  last_used_at?: string;
}

export interface MintMcpConnectorInput {
  label?: string;
  /** Agent slug bound when the connector is used (default `grok`). Empty clears. */
  slug?: string | null;
}

export interface MintMcpConnectorResult {
  connector: McpConnectorView;
  /** Plaintext secret — returned once at mint. */
  token: string;
}

function connectorKey(id: string) {
  return ["mcp_connectors", id];
}
function hashKey(hash: string) {
  return ["mcp_connector_hashes", hash];
}
function userConnectorKey(userId: string, id: string) {
  return ["user_mcp_connectors", userId, id];
}
function userConnectorsPrefix(userId: string) {
  return ["user_mcp_connectors", userId];
}

export function toMcpConnectorView(row: McpConnectorRecord): McpConnectorView {
  return {
    id: row.id,
    prefix: row.prefix,
    label: row.label,
    slug: row.slug,
    created_at: row.created_at,
    last_used_at: row.last_used_at,
  };
}

export async function hashConnectorToken(token: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  return Array.from(new Uint8Array(buf), (b) =>
    b.toString(16).padStart(2, "0")
  ).join("");
}

function resolveMintSlug(input: MintMcpConnectorInput): string | null {
  if (input.slug === undefined) return "grok";
  if (input.slug === null) return null;
  const trimmed = String(input.slug).trim().toLowerCase();
  if (!trimmed) return null;
  assertValidAgentSlug(trimmed);
  return trimmed;
}

export async function mintMcpConnector(
  kv: Deno.Kv,
  userId: string,
  input: MintMcpConnectorInput = {},
): Promise<MintMcpConnectorResult> {
  const active = await listMcpConnectorRecords(kv, userId);
  if (active.length >= MAX_MCP_CONNECTORS) {
    throw forbidden(
      `Too many MCP connector keys (max ${MAX_MCP_CONNECTORS}); revoke one first`,
    );
  }
  const label = (input.label?.trim() || "Grok Bot").slice(0, 64);
  const slug = resolveMintSlug(input);
  const token = `${MCP_CONNECTOR_PREFIX}${randomToken()}`;
  const token_hash = await hashConnectorToken(token);
  const id = crypto.randomUUID();
  const row: McpConnectorRecord = {
    id,
    user_id: userId,
    token_hash,
    prefix: token.slice(0, 12),
    label,
    slug,
    created_at: new Date().toISOString(),
  };
  const tx = kv.atomic();
  tx.set(connectorKey(id), row);
  tx.set(hashKey(token_hash), id);
  tx.set(userConnectorKey(userId, id), id);
  const res = await tx.commit();
  if (!res.ok) throw conflict("Connector create conflict");
  return { connector: toMcpConnectorView(row), token };
}

export async function listMcpConnectorRecords(
  kv: Deno.Kv,
  userId: string,
): Promise<McpConnectorRecord[]> {
  const rows: McpConnectorRecord[] = [];
  const iter = kv.list<string>({ prefix: userConnectorsPrefix(userId) });
  for await (const entry of iter) {
    const got = await kv.get<McpConnectorRecord>(connectorKey(entry.value));
    if (got.value && !got.value.revoked_at) rows.push(got.value);
  }
  rows.sort((a, b) => b.created_at.localeCompare(a.created_at));
  return rows;
}

export async function lookupMcpConnectorByToken(
  kv: Deno.Kv,
  token: string,
): Promise<McpConnectorRecord | null> {
  if (!isMcpConnectorToken(token)) return null;
  const hash = await hashConnectorToken(token);
  const idRes = await kv.get<string>(hashKey(hash));
  if (!idRes.value) return null;
  const row = await kv.get<McpConnectorRecord>(connectorKey(idRes.value));
  if (!row.value || row.value.revoked_at) return null;
  return row.value;
}

export async function touchMcpConnectorLastUsed(
  kv: Deno.Kv,
  row: McpConnectorRecord,
): Promise<void> {
  const updated: McpConnectorRecord = {
    ...row,
    last_used_at: new Date().toISOString(),
  };
  await kv.set(connectorKey(row.id), updated);
}

export async function revokeMcpConnector(
  kv: Deno.Kv,
  userId: string,
  connectorId: string,
): Promise<void> {
  const got = await kv.get<McpConnectorRecord>(connectorKey(connectorId));
  if (!got.value || got.value.user_id !== userId) {
    throw notFound("connector");
  }
  if (got.value.revoked_at) return;
  const revoked: McpConnectorRecord = {
    ...got.value,
    revoked_at: new Date().toISOString(),
  };
  const tx = kv.atomic();
  tx.set(connectorKey(connectorId), revoked);
  tx.delete(hashKey(got.value.token_hash));
  tx.delete(userConnectorKey(userId, connectorId));
  const res = await tx.commit();
  if (!res.ok) throw conflict("Connector revoke conflict");
}
