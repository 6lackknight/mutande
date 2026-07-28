import { HubError } from "./errors.ts";

const RESERVED_AGENT_SLUGS = new Set(["default", "all"]);
const AGENT_SLUG_RE = /^[a-z0-9-]{1,32}$/;

export interface ParsedDisplayAddress {
  local: string;
  orgSlug: string;
  agentSlug?: string;
}

export function isBroadcastHandle(handle: string): boolean {
  return handle.startsWith("@all@");
}

export function broadcastHandle(orgSlug: string): string {
  return `@all@${orgSlug}`;
}

export function assertValidAgentSlug(slug: string): void {
  if (!AGENT_SLUG_RE.test(slug)) {
    throw new HubError(
      "Agent slug must be 1–32 lowercase letters, digits, or hyphens",
      "invalid_agent_slug",
    );
  }
  if (RESERVED_AGENT_SLUGS.has(slug)) {
    throw new HubError(`Agent slug '${slug}' is reserved`, "invalid_agent_slug");
  }
}

/** Parse `alice@acme`, `alice@acme/claude`, or `@all@acme`. */
export function parseDisplayAddress(input: string): ParsedDisplayAddress {
  const trimmed = input.trim();
  if (isBroadcastHandle(trimmed)) {
    const orgSlug = trimmed.slice("@all@".length);
    if (!orgSlug) {
      throw new HubError("Invalid broadcast handle", "invalid_handle");
    }
    return { local: "@all", orgSlug, agentSlug: undefined };
  }

  const slash = trimmed.indexOf("/");
  const base = slash >= 0 ? trimmed.slice(0, slash) : trimmed;
  const agentSlug = slash >= 0 ? trimmed.slice(slash + 1) : undefined;
  if (agentSlug !== undefined) {
    if (!agentSlug) throw new HubError("Missing agent slug after /", "invalid_handle");
    assertValidAgentSlug(agentSlug);
  }

  const at = base.lastIndexOf("@");
  if (at <= 0 || at === base.length - 1) {
    throw new HubError("Invalid handle format", "invalid_handle");
  }
  const local = base.slice(0, at);
  const orgSlug = base.slice(at + 1);
  if (local.toLowerCase() === "@all" || local.toLowerCase().startsWith("@all")) {
    throw new HubError("Handle cannot use @all broadcast prefix", "invalid_handle");
  }
  return { local, orgSlug, agentSlug };
}

export function bareHandle(local: string, orgSlug: string): string {
  return `${local}@${orgSlug}`;
}

export function formatDisplayAddress(
  local: string,
  orgSlug: string,
  agentSlug?: string,
): string {
  const base = bareHandle(local, orgSlug);
  return agentSlug ? `${base}/${agentSlug}` : base;
}

export function stripAgentSuffix(display: string): string {
  const slash = display.indexOf("/");
  return slash >= 0 ? display.slice(0, slash) : display;
}

export function agentSuffix(display: string): string | undefined {
  const slash = display.indexOf("/");
  return slash >= 0 ? display.slice(slash + 1) : undefined;
}

/** Wire path: `acme/alice/claude` (org/user/agent). */
export function formatWirePath(orgSlug: string, local: string, agentSlug: string): string {
  return `${orgSlug}/${local}/${agentSlug}`;
}

export function parseWirePath(path: string): { orgSlug: string; local: string; agentSlug: string } {
  const parts = path.split("/");
  if (parts.length !== 3 || !parts[0] || !parts[1] || !parts[2]) {
    throw new HubError("Invalid wire path (expected org/user/agent)", "invalid_handle");
  }
  assertValidAgentSlug(parts[2]);
  return { orgSlug: parts[0], local: parts[1], agentSlug: parts[2] };
}

export function assertHandleLocal(local: string): void {
  if (local.toLowerCase() === "@all" || local.toLowerCase().startsWith("@all")) {
    throw new HubError("Handle cannot use @all broadcast prefix", "invalid_handle");
  }
}

/** Legacy user handle parse (no agent suffix). */
export function parseUserHandle(handle: string): { local: string; orgSlug: string } {
  const { local, orgSlug } = parseDisplayAddress(handle);
  return { local, orgSlug };
}
