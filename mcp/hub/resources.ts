/**
 * Hosted MCP has no access to ChatGPT/Claude sandbox filesystems.
 * Resources must carry inline content (or base64) — never host-only paths.
 */

export const HOST_PATH_REFUSAL =
  "Hosted MCP cannot read host sandbox file paths (e.g. /mnt/data/…). " +
  "Pass file contents inline: resources[].content (text) or resources[].content_base64 " +
  "(binary/text). Do not pass ChatGPT/Claude local paths alone.";

/** Absolute paths that only exist inside a host sandbox, not on mcp.mutande.online. */
const HOST_SANDBOX_PATH =
  /^\/(mnt\/data|tmp|var\/folders|home\/[^/]+\/(uploads|files|sandbox)|Users\/|private\/var)\b/i;

function asRecord(v: unknown): Record<string, unknown> | null {
  if (v && typeof v === "object" && !Array.isArray(v)) {
    return v as Record<string, unknown>;
  }
  return null;
}

function nonEmptyString(v: unknown): string | null {
  return typeof v === "string" && v.trim() ? v : null;
}

/** True when the resource already carries readable payload bytes/text. */
export function resourceHasInlineContent(resource: unknown): boolean {
  const r = asRecord(resource);
  if (!r) return false;
  if (nonEmptyString(r.content)) return true;
  if (nonEmptyString(r.content_base64)) return true;
  if (nonEmptyString(r.data)) return true;
  if (nonEmptyString(r.body)) return true;
  if (typeof r.bytes === "string" && r.bytes.trim()) return true;
  return false;
}

export function resourceHostOnlyPath(resource: unknown): string | null {
  const r = asRecord(resource);
  if (!r || resourceHasInlineContent(r)) return null;
  for (const key of ["path", "uri", "file", "filepath", "local_path"] as const) {
    const p = nonEmptyString(r[key]);
    if (!p) continue;
    // file:// URIs → path check
    const path = p.startsWith("file://") ? p.slice("file://".length) : p;
    if (HOST_SANDBOX_PATH.test(path) || path.startsWith("/")) {
      return p;
    }
  }
  return null;
}

/**
 * Normalize / validate bundle.resources for hosted forward/reply.
 * - Rejects host-sandbox paths without inline content (clear error).
 * - Accepts content / content_base64 / data / body.
 * - Leaves path as a label only when inline content is present.
 */
export function prepareBundleResources(
  bundle: Record<string, unknown>,
): Record<string, unknown> {
  const raw = bundle.resources;
  if (raw == null) return bundle;
  if (!Array.isArray(raw)) {
    throw new Error("bundle.resources must be an array");
  }
  if (raw.length === 0) return bundle;

  const out: Record<string, unknown>[] = [];
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i];
    const hostPath = resourceHostOnlyPath(item);
    if (hostPath && !resourceHasInlineContent(item)) {
      throw new Error(
        `${HOST_PATH_REFUSAL} Offending resources[${i}]: ${hostPath}`,
      );
    }
    const r = asRecord(item);
    if (!r) {
      throw new Error(`bundle.resources[${i}] must be an object`);
    }
    // Path-only absolute refs with no inline payload (non-sandbox absolute) still fail.
    const pathOnly = nonEmptyString(r.path) ?? nonEmptyString(r.uri) ??
      nonEmptyString(r.file) ?? nonEmptyString(r.filepath);
    if (pathOnly && pathOnly.startsWith("/") && !resourceHasInlineContent(r)) {
      throw new Error(
        `${HOST_PATH_REFUSAL} Offending resources[${i}]: ${pathOnly}`,
      );
    }
    if (!resourceHasInlineContent(r) && !nonEmptyString(r.name) && !pathOnly) {
      throw new Error(
        `bundle.resources[${i}] needs content, content_base64, or a name with inline bytes`,
      );
    }
    // Prefer explicit text content; decode base64 into content when text-ish and content missing.
    const next: Record<string, unknown> = { ...r };
    if (!nonEmptyString(next.content) && nonEmptyString(next.content_base64)) {
      try {
        const decoded = atob(String(next.content_base64).replace(/\s+/g, ""));
        // Keep base64 for binary; also expose utf-8 text when it looks like text.
        if (!/[\x00-\x08\x0e-\x1f]/.test(decoded)) {
          next.content = decoded;
        }
      } catch {
        throw new Error(
          `bundle.resources[${i}].content_base64 is not valid base64`,
        );
      }
    }
    out.push(next);
  }
  return { ...bundle, resources: out };
}
