/** Agent intro card — hub-readable profile, not the L1 capability connect handshake. */

export interface AgentHandshakeProfile {
  host?: string;
  address?: string;
  models?: string[];
  skills?: string[];
  ask_me_about?: string[];
  preferred_file_format?: string;
  other_tools?: string[];
  published_at?: string;
}

/** Client body for PUT /v1/agents/:id/handshake. */
export type HandshakeInput = {
  host?: string;
  address?: string;
  models?: string[];
  skills?: string[];
  ask_me_about?: string[];
  preferred_file_format?: string;
  other_tools?: string[];
};

const MAX_ITEMS = 12;
const MAX_LEN = 80;
const MAX_FORMAT = 40;

/** Tokens, keys, paths — never stored on a handshake card. */
export function looksLikeSecret(value: string): boolean {
  const t = value.trim();
  if (!t) return false;
  if (/^(sk-|sk_live_|sk_test_|ghp_|github_pat_|xox[baprs]-|Bearer\s)/i.test(t)) {
    return true;
  }
  if (/(api[_-]?key|secret|token|password|credential)\s*[:=]/i.test(t)) {
    return true;
  }
  if (/^(\/Users\/|\/home\/|~\/|file:\/\/|[A-Za-z]:\\)/.test(t)) return true;
  return false;
}

/** @deprecated use looksLikeSecret */
export const looksSecretOrPath = looksLikeSecret;

function cleanOne(value: unknown, maxLen: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const t = value.trim().slice(0, maxLen);
  if (!t || looksLikeSecret(t)) return undefined;
  return t;
}

function cleanList(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  const out: string[] = [];
  const seen = new Set<string>();
  for (const item of value) {
    const t = cleanOne(item, MAX_LEN);
    if (!t) continue;
    const key = t.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(t);
    if (out.length >= MAX_ITEMS) break;
  }
  return out.length > 0 ? out : undefined;
}

/** Strip secrets/paths and cap size. Empty fields are omitted. */
export function sanitizeHandshake(
  input: HandshakeInput | Record<string, unknown>,
  publishedAt: string,
): AgentHandshakeProfile {
  const host = cleanOne(input.host, MAX_LEN);
  const address = cleanOne(input.address, MAX_LEN);
  const models = cleanList(input.models);
  const skills = cleanList(input.skills);
  const askMeAbout = cleanList(input.ask_me_about);
  const preferred = cleanOne(input.preferred_file_format, MAX_FORMAT);
  const otherTools = cleanList(input.other_tools);
  const card: AgentHandshakeProfile = { published_at: publishedAt };
  if (host) card.host = host;
  if (address) card.address = address;
  if (models) card.models = models;
  if (skills) card.skills = skills;
  if (askMeAbout) card.ask_me_about = askMeAbout;
  if (preferred) card.preferred_file_format = preferred;
  if (otherTools) card.other_tools = otherTools;
  return card;
}

export function isHandshakeProfile(
  value: unknown,
): value is AgentHandshakeProfile {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
