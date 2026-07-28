import { HubError } from "./errors.ts";

const RESERVED_AGENT_SLUGS = new Set(["default", "all"]);
const AGENT_SLUG_RE = /^[a-z0-9-]{1,32}$/;

/** How a display address should be resolved. */
export type AddressKind = "user" | "org_broadcast" | "self_agent" | "my_agents";

export interface ParsedDisplayAddress {
  kind: AddressKind;
  local: string;
  orgSlug: string;
  agentSlug?: string;
}

/** Org-wide broadcast: `@all@org`. */
export function isBroadcastHandle(handle: string): boolean {
  return handle.startsWith("@all@");
}

/** Self fan-out to all of the current user's agents: bare `@all`. */
export function isMyAgentsHandle(handle: string): boolean {
  return handle.trim() === "@all";
}

export function broadcastHandle(orgSlug: string): string {
  return `@all@${orgSlug}`;
}

export function myAgentsHandle(): string {
  return "@all";
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

/**
 * Parse display addresses:
 * - `alice@acme`, `alice@acme/claude`
 * - `@all@acme` (org broadcast)
 * - `@all` (all of my agents)
 * - `@claude` (shorthand for current user's agent slug)
 */
export function parseDisplayAddress(input: string): ParsedDisplayAddress {
  const trimmed = input.trim();

  if (isMyAgentsHandle(trimmed)) {
    return { kind: "my_agents", local: "@all", orgSlug: "", agentSlug: undefined };
  }

  if (isBroadcastHandle(trimmed)) {
    const orgSlug = trimmed.slice("@all@".length);
    if (!orgSlug) {
      throw new HubError("Invalid broadcast handle", "invalid_handle");
    }
    return { kind: "org_broadcast", local: "@all", orgSlug, agentSlug: undefined };
  }

  // Self-agent shorthand: `@claude` (single leading @, no other @ or /).
  if (
    trimmed.startsWith("@") &&
    !trimmed.includes("/", 1) &&
    trimmed.indexOf("@", 1) === -1
  ) {
    const slug = trimmed.slice(1);
    if (!slug) throw new HubError("Invalid handle format", "invalid_handle");
    assertValidAgentSlug(slug);
    return { kind: "self_agent", local: "", orgSlug: "", agentSlug: slug };
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
  return { kind: "user", local, orgSlug, agentSlug };
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

/** Legacy user handle parse (no agent suffix). Rejects shorthand / my-agents forms. */
export function parseUserHandle(handle: string): { local: string; orgSlug: string } {
  const parsed = parseDisplayAddress(handle);
  if (parsed.kind !== "user" && parsed.kind !== "org_broadcast") {
    throw new HubError("Invalid handle format", "invalid_handle");
  }
  return { local: parsed.local, orgSlug: parsed.orgSlug };
}
