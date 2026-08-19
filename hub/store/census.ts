import type { Agent, BillingLedger, OpsCensus, Org, RegistryListing, ThreadMeta, User } from "./types.ts";

const DAY_MS = 24 * 60 * 60 * 1000;
const USERS_TARGET = 20;
const REPLIED_THREADS_TARGET = 100;

function inLastDays(iso: string | undefined, days: number, now: number): boolean {
  if (!iso) return false;
  const t = Date.parse(iso);
  return !Number.isNaN(t) && now - t < days * DAY_MS;
}

async function collect<T>(kv: Deno.Kv, prefix: Deno.KvKey): Promise<T[]> {
  const items: T[] = [];
  const iter = kv.list<T>({ prefix });
  for await (const entry of iter) {
    if (entry.value) items.push(entry.value);
  }
  return items;
}

/** Hub counts for the Phase 1 evidence scoreboard + KV wipe watch. No PII. */
export async function computeOpsCensus(
  kv: Deno.Kv,
  nowMs: number = Date.now(),
): Promise<OpsCensus> {
  const [orgs, users, devices, agents, threads, ledgers, listings] = await Promise.all([
    collect<Org>(kv, ["orgs"]),
    collect<User>(kv, ["users"]),
    collect<unknown>(kv, ["devices"]),
    collect<Agent>(kv, ["agents"]),
    collect<ThreadMeta>(kv, ["threads"]),
    collect<BillingLedger>(kv, ["billing_ledgers"]),
    collect<RegistryListing>(kv, ["registry_listings"]),
  ]);

  const membersByOrg = new Map<string, number>();
  const memberIter = kv.list({ prefix: ["org_members"] });
  for await (const entry of memberIter) {
    const orgId = entry.key[1];
    if (typeof orgId !== "string") continue;
    membersByOrg.set(orgId, (membersByOrg.get(orgId) ?? 0) + 1);
  }

  let orgsWithTwoPlusMembers = 0;
  for (const count of membersByOrg.values()) {
    if (count >= 2) orgsWithTwoPlusMembers += 1;
  }

  const slugsByUser = new Map<string, Set<string>>();
  for (const agent of agents) {
    const slug = agent.slug?.trim().toLowerCase();
    if (!agent.user_id || !slug) continue;
    const set = slugsByUser.get(agent.user_id) ?? new Set<string>();
    set.add(slug);
    slugsByUser.set(agent.user_id, set);
  }
  let multiHostUsers = 0;
  for (const slugs of slugsByUser.values()) {
    if (slugs.size >= 2) multiHostUsers += 1;
  }

  let repliedThreads = 0;
  const activeUserIds7d = new Set<string>();
  const activeUserIds30d = new Set<string>();
  for (const thread of threads) {
    if ((thread.reply_count ?? 0) >= 1) repliedThreads += 1;
    const ids = [
      thread.from_user_id,
      ...(thread.participant_user_ids ?? []),
    ].filter(Boolean);
    if (inLastDays(thread.updated_at, 7, nowMs)) {
      for (const id of ids) activeUserIds7d.add(id);
    }
    if (inLastDays(thread.updated_at, 30, nowMs)) {
      for (const id of ids) activeUserIds30d.add(id);
    }
  }

  let pairingFlagsOpen = 0;
  const flagIter = kv.list({ prefix: ["pairing_ops_flags"] });
  for await (const entry of flagIter) {
    if (entry.value) pairingFlagsOpen += 1;
  }

  const ledgerOrgsNonzero = ledgers.filter((l) => (l.balance_cents ?? 0) > 0).length;
  const creditsOutstandingCents = ledgers.reduce(
    (sum, l) => sum + Math.max(0, l.balance_cents ?? 0),
    0,
  );
  const publishedListings = listings.filter((l) => l.status === "published").length;
  const billedDeliveries = await countPrefix(kv, ["enterprise_metrics"]);

  const migrateBeforeKeep = orgsWithTwoPlusMembers >= 1 ||
    ledgerOrgsNonzero >= 1 ||
    publishedListings >= 1;

  return {
    users: users.length,
    orgs: orgs.length,
    devices: devices.length,
    agents: agents.length,
    multi_host_users: multiHostUsers,
    orgs_with_2plus_members: orgsWithTwoPlusMembers,
    users_active_7d: activeUserIds7d.size,
    users_active_30d: activeUserIds30d.size,
    threads: threads.length,
    replied_threads: repliedThreads,
    published_listings: publishedListings,
    ledger_orgs_nonzero: ledgerOrgsNonzero,
    credits_outstanding_cents: creditsOutstandingCents,
    billed_deliveries: billedDeliveries,
    pairing_flags_open: pairingFlagsOpen,
    storage_status: migrateBeforeKeep ? "migrate_before_keep" : "fresh_start_ok",
    targets: {
      users: USERS_TARGET,
      replied_threads: REPLIED_THREADS_TARGET,
    },
  };
}

async function countPrefix(kv: Deno.Kv, prefix: Deno.KvKey): Promise<number> {
  let n = 0;
  const iter = kv.list({ prefix });
  for await (const entry of iter) {
    if (entry.value) n += 1;
  }
  return n;
}
