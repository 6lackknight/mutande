/**
 * One-shot KV migration: normalize every stored handle to lowercase.
 *
 * Handles are lowercase-by-construction today, but early prod data was written
 * before normalization was enforced everywhere (e.g. a `["handles", "Orinea@tbhco"]`
 * index key), which made lookups casing-sensitive. This migration rewrites:
 *
 * - `["handles", <handle>]` index keys (the resolution-critical index)
 * - `users[].handle`
 * - `external_contacts[].user_a_handle` / `user_b_handle` snapshots
 * - `pair_requests[].requester_handle` / `target_handle`
 * - `pairing_pins[].handle`
 *
 * Thread `from`/`audience` display strings are intentionally left alone: they
 * are display-only, and every read path resolves through normalized lookups.
 *
 * The migration is idempotent and guarded by a marker record so it costs a
 * single KV get on every boot after the first run.
 */

import type {
  ExternalContactLink,
  PairRequest,
  PairingPin,
  User,
} from "./types.ts";

export const LOWERCASE_HANDLES_MIGRATION_KEY: Deno.KvKey = [
  "migrations",
  "lowercase_handles_v1",
];

export interface HandleMigrationReport {
  handle_keys: number;
  users: number;
  external_links: number;
  pair_requests: number;
  pairing_pins: number;
  /** Raw handle-index keys we could not rewrite (lowercase key already maps to a different user). */
  conflicts: string[];
  completed_at: string;
}

function lower(handle: string): string {
  return handle.trim().toLowerCase();
}

/**
 * Run the lowercase-handles migration. Returns the report when work ran, or
 * null when the marker says it already completed. `force` reruns regardless.
 */
export async function migrateHandlesToLowercase(
  kv: Deno.Kv,
  opts: { force?: boolean } = {},
): Promise<HandleMigrationReport | null> {
  if (!opts.force) {
    const done = await kv.get(LOWERCASE_HANDLES_MIGRATION_KEY);
    if (done.value) return null;
  }

  const report: HandleMigrationReport = {
    handle_keys: 0,
    users: 0,
    external_links: 0,
    pair_requests: 0,
    pairing_pins: 0,
    conflicts: [],
    completed_at: "",
  };

  // 1. Handle index: move mixed-case keys to their lowercase form.
  for await (const entry of kv.list<string>({ prefix: ["handles"] })) {
    const raw = entry.key[1];
    if (typeof raw !== "string") continue;
    const normalized = lower(raw);
    if (normalized === raw) continue;
    const existing = await kv.get<string>(["handles", normalized]);
    if (existing.value && existing.value !== entry.value) {
      // Two distinct users behind the same lowercase handle — never delete
      // either mapping; surface for manual ops instead.
      report.conflicts.push(raw);
      continue;
    }
    const res = await kv.atomic()
      .check(entry)
      .check(existing)
      .set(["handles", normalized], entry.value)
      .delete(entry.key)
      .commit();
    if (res.ok) report.handle_keys++;
    else report.conflicts.push(raw);
  }

  // 2. User records.
  for await (const entry of kv.list<User>({ prefix: ["users"] })) {
    const user = entry.value;
    if (!user?.handle) continue;
    const normalized = lower(user.handle);
    if (normalized === user.handle) continue;
    const res = await kv.atomic()
      .check(entry)
      .set(entry.key, { ...user, handle: normalized })
      .commit();
    if (res.ok) report.users++;
  }

  // 3. External contact link handle snapshots.
  for await (
    const entry of kv.list<ExternalContactLink>({
      prefix: ["external_contacts"],
    })
  ) {
    const link = entry.value;
    if (!link?.user_a_handle || !link.user_b_handle) continue;
    const a = lower(link.user_a_handle);
    const b = lower(link.user_b_handle);
    if (a === link.user_a_handle && b === link.user_b_handle) continue;
    const res = await kv.atomic()
      .check(entry)
      .set(entry.key, { ...link, user_a_handle: a, user_b_handle: b })
      .commit();
    if (res.ok) report.external_links++;
  }

  // 4. Pair requests.
  for await (
    const entry of kv.list<PairRequest>({ prefix: ["pair_requests"] })
  ) {
    const req = entry.value;
    if (!req?.requester_handle || !req.target_handle) continue;
    const requester = lower(req.requester_handle);
    const target = lower(req.target_handle);
    if (requester === req.requester_handle && target === req.target_handle) {
      continue;
    }
    const res = await kv.atomic()
      .check(entry)
      .set(entry.key, {
        ...req,
        requester_handle: requester,
        target_handle: target,
      })
      .commit();
    if (res.ok) report.pair_requests++;
  }

  // 5. Pairing PINs (short-TTL, but keep the sweep complete).
  for await (const entry of kv.list<PairingPin>({ prefix: ["pairing_pins"] })) {
    const pin = entry.value;
    if (!pin?.handle) continue;
    const normalized = lower(pin.handle);
    if (normalized === pin.handle) continue;
    const res = await kv.atomic()
      .check(entry)
      .set(entry.key, { ...pin, handle: normalized })
      .commit();
    if (res.ok) report.pairing_pins++;
  }

  report.completed_at = new Date().toISOString();
  await kv.set(LOWERCASE_HANDLES_MIGRATION_KEY, report);
  return report;
}
