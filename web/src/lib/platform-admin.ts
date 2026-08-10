/** Mirrors hub `store/platform_admin.ts` — Auth0 SuperAdmin for product-owner ops. */

const DEFAULT_PLATFORM_ADMIN_ROLES = ["SuperAdmin", "rol_jsa0BZq7uzz2K4RG"];

export const AUTH0_ROLES_CLAIM_KEYS = [
  "https://hub.mutande.app/roles",
  "https://mutande.app/roles",
  "https://mutande.online/roles",
  "roles",
] as const;

export function platformAdminRoles(): string[] {
  const raw = process.env.MUTANDE_PLATFORM_ADMIN_ROLES?.trim();
  if (!raw) return [...DEFAULT_PLATFORM_ADMIN_ROLES];
  return raw.split(",").map((s) => s.trim()).filter(Boolean);
}

export function isPlatformOpsAdmin(
  roles: readonly string[] | undefined,
): boolean {
  if (!roles?.length) return false;
  const have = new Set(roles);
  return platformAdminRoles().some((r) => have.has(r));
}

function pushRole(out: Set<string>, item: unknown): void {
  if (typeof item === "string" && item.trim()) {
    out.add(item.trim());
    return;
  }
  if (item && typeof item === "object") {
    const rec = item as Record<string, unknown>;
    if (typeof rec.name === "string" && rec.name.trim()) out.add(rec.name.trim());
    if (typeof rec.id === "string" && rec.id.trim()) out.add(rec.id.trim());
  }
}

/** Pull role names/ids from an Auth0 JWT payload or session user object. */
export function extractAuth0Roles(payload: Record<string, unknown>): string[] {
  const out = new Set<string>();
  for (const key of AUTH0_ROLES_CLAIM_KEYS) {
    const value = payload[key];
    if (Array.isArray(value)) {
      for (const item of value) pushRole(out, item);
      continue;
    }
    if (typeof value === "string" && value.trim()) {
      for (const part of value.split(/[,\s]+/)) {
        if (part.trim()) out.add(part.trim());
      }
    }
  }
  return [...out];
}

/** Decode JWT payload (no verify — UI gating only; hub still enforces). */
export function rolesFromJwt(token: string | undefined | null): string[] {
  if (!token) return [];
  const parts = token.split(".");
  if (parts.length < 2) return [];
  try {
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const json = Buffer.from(b64, "base64").toString("utf8");
    const payload = JSON.parse(json) as Record<string, unknown>;
    return extractAuth0Roles(payload);
  } catch {
    return [];
  }
}
