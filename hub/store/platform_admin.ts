/** Auth0 role name (and optional role id) for product-owner ops. */
const DEFAULT_PLATFORM_ADMIN_ROLES = ["SuperAdmin", "rol_jsa0BZq7uzz2K4RG"];

/** Custom claim namespaces we accept for Auth0 role arrays on access tokens. */
export const AUTH0_ROLES_CLAIM_KEYS = [
  "https://hub.mutande.app/roles",
  "https://mutande.app/roles",
  "https://mutande.online/roles",
  "roles",
] as const;

export function platformAdminRoles(): string[] {
  let raw: string | undefined;
  try {
    raw = Deno.env.get("MUTANDE_PLATFORM_ADMIN_ROLES")?.trim();
  } catch {
    // Tests / restricted workers without --allow-env.
    return [...DEFAULT_PLATFORM_ADMIN_ROLES];
  }
  if (!raw) return [...DEFAULT_PLATFORM_ADMIN_ROLES];
  return raw.split(",").map((s) => s.trim()).filter(Boolean);
}

export function isPlatformOpsAdmin(roles: readonly string[] | undefined): boolean {
  if (!roles?.length) return false;
  const have = new Set(roles);
  return platformAdminRoles().some((r) => have.has(r));
}

export function extractAuth0Roles(payload: Record<string, unknown>): string[] {
  const out = new Set<string>();
  for (const key of AUTH0_ROLES_CLAIM_KEYS) {
    const value = payload[key];
    if (!Array.isArray(value)) continue;
    for (const item of value) {
      if (typeof item === "string" && item.trim()) out.add(item.trim());
    }
  }
  return [...out];
}
