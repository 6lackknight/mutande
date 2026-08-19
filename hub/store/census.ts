import { parseDisplayAddress, stripAgentSuffix } from "./address.ts";
import type {
  Agent,
  BillingLedger,
  OpsCensus,
  OpsGraph,
  OpsGraphEdge,
  OpsGraphEdgeKind,
  OpsGraphNode,
  Org,
  RegistryListing,
  ThreadMeta,
  User,
} from "./types.ts";

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

function orgNodeId(id: string) {
  return `org:${id}`;
}
function userNodeId(id: string) {
  return `user:${id}`;
}
function agentNodeId(id: string) {
  return `agent:${id}`;
}

function edgeKey(a: string, b: string, kind: OpsGraphEdgeKind): string {
  return a < b ? `${kind}|${a}|${b}` : `${kind}|${b}|${a}`;
}

function addEdge(
  edges: Map<string, OpsGraphEdge>,
  from: string,
  to: string,
  kind: OpsGraphEdgeKind,
  weight: number,
): void {
  if (!from || !to || from === to) return;
  if (kind !== "slot" && weight <= 0) return;
  const key = edgeKey(from, to, kind);
  const existing = edges.get(key);
  if (existing) {
    existing.weight += weight;
    if (kind !== "slot") existing.threads += 1;
    return;
  }
  edges.set(key, {
    from,
    to,
    kind,
    weight,
    threads: kind === "slot" ? 0 : 1,
  });
}

function userIdFromNode(id: string): string | null {
  return id.startsWith("user:") ? id.slice(5) : null;
}

/** Routing graph for ops — handles/slugs only, no mail content. */
export function buildOpsGraph(input: {
  orgs: Org[];
  users: User[];
  agents: Agent[];
  threads: ThreadMeta[];
  membersByOrg: Map<string, string[]>;
}): OpsGraph {
  const nodes: OpsGraphNode[] = [];
  const usersById = new Map(input.users.map((u) => [u.id, u]));
  const usersByHandle = new Map<string, User>();
  for (const user of input.users) {
    if (user.handle) usersByHandle.set(user.handle.toLowerCase(), user);
  }
  const agentsById = new Map(input.agents.map((a) => [a.id, a]));
  const agentsByUser = new Map<string, Agent[]>();
  for (const agent of input.agents) {
    const list = agentsByUser.get(agent.user_id) ?? [];
    list.push(agent);
    agentsByUser.set(agent.user_id, list);
  }

  for (const org of input.orgs) {
    nodes.push({
      id: orgNodeId(org.id),
      kind: "org",
      label: org.slug,
    });
  }
  for (const user of input.users) {
    if (!user.org_id) continue;
    nodes.push({
      id: userNodeId(user.id),
      kind: "user",
      label: (user.handle ?? user.id.slice(0, 8)).toLowerCase(),
      parent_id: orgNodeId(user.org_id),
    });
  }
  for (const agent of input.agents) {
    nodes.push({
      id: agentNodeId(agent.id),
      kind: "agent",
      label: agent.slug,
      parent_id: userNodeId(agent.user_id),
    });
  }

  const nodeIds = new Set(nodes.map((n) => n.id));
  const edges = new Map<string, OpsGraphEdge>();

  for (const user of input.users) {
    if (!user.org_id) continue;
    const uid = userNodeId(user.id);
    const oid = orgNodeId(user.org_id);
    if (nodeIds.has(oid)) {
      addEdge(edges, oid, uid, "slot", 0);
    }
    for (const agent of agentsByUser.get(user.id) ?? []) {
      addEdge(edges, uid, agentNodeId(agent.id), "slot", 0);
    }
  }

  for (const thread of input.threads) {
    const weight = 1 + Math.max(0, thread.reply_count ?? 0);
    const sender = thread.from_user_id;
    const fromAgent = thread.from_agent_id
      ? agentNodeId(thread.from_agent_id)
      : null;
    const audienceAgent = thread.audience_agent_id
      ? agentNodeId(thread.audience_agent_id)
      : null;

    let parsed: ReturnType<typeof parseDisplayAddress> | null = null;
    try {
      parsed = parseDisplayAddress(thread.audience ?? "");
    } catch {
      parsed = null;
    }

    const others = new Set<string>();
    if (thread.participant_user_ids?.length) {
      for (const id of thread.participant_user_ids) {
        if (id && id !== sender) others.add(id);
      }
    }

    if (parsed?.kind === "my_agents" || thread.audience === "@all") {
      const agentIds = (agentsByUser.get(sender) ?? [])
        .map((a) => agentNodeId(a.id))
        .filter((id) => nodeIds.has(id));
      const origin = fromAgent && nodeIds.has(fromAgent) ? fromAgent : null;
      const siblings = origin
        ? agentIds.filter((id) => id !== origin)
        : agentIds;
      if (origin && siblings.length > 0) {
        for (const sid of siblings) addEdge(edges, origin, sid, "self", weight);
      } else if (agentIds.length >= 2) {
        for (let i = 0; i < agentIds.length; i++) {
          for (let j = i + 1; j < agentIds.length; j++) {
            addEdge(edges, agentIds[i]!, agentIds[j]!, "self", weight);
          }
        }
      }
      continue;
    }

    if (parsed?.kind === "self_agent") {
      if (fromAgent && audienceAgent && nodeIds.has(fromAgent) && nodeIds.has(audienceAgent)) {
        addEdge(edges, fromAgent, audienceAgent, "self", weight);
      } else if (fromAgent && nodeIds.has(fromAgent)) {
        const siblings = (agentsByUser.get(sender) ?? [])
          .map((a) => agentNodeId(a.id))
          .filter((id) => id !== fromAgent);
        for (const sid of siblings) addEdge(edges, fromAgent, sid, "self", weight);
      }
      continue;
    }

    if (parsed?.kind === "org_broadcast" || thread.kind === "broadcast") {
      const memberIds = input.membersByOrg.get(thread.org_id) ?? [];
      for (const id of memberIds) {
        if (id !== sender) others.add(id);
      }
      for (const id of others) {
        addEdge(edges, userNodeId(sender), userNodeId(id), "broadcast", weight);
      }
      continue;
    }

    if (others.size === 0 && parsed?.kind === "user") {
      const handle = stripAgentSuffix(
        `${parsed.local}@${parsed.orgSlug}`,
      ).toLowerCase();
      const peer = usersByHandle.get(handle);
      if (peer && peer.id !== sender) others.add(peer.id);
    }

    const kind: OpsGraphEdgeKind = thread.external_link_id
      ? "external"
      : "org";

    if (
      others.size === 0 &&
      fromAgent &&
      audienceAgent &&
      nodeIds.has(fromAgent) &&
      nodeIds.has(audienceAgent)
    ) {
      const fromUser = agentsById.get(thread.from_agent_id ?? "")?.user_id;
      const toUser = agentsById.get(thread.audience_agent_id ?? "")?.user_id;
      const edgeKind: OpsGraphEdgeKind = fromUser && toUser && fromUser === toUser
        ? "self"
        : kind;
      addEdge(edges, fromAgent, audienceAgent, edgeKind, weight);
      continue;
    }

    for (const id of others) {
      addEdge(edges, userNodeId(sender), userNodeId(id), kind, weight);
    }
  }

  const traffic = [...edges.values()].filter((e) => e.kind !== "slot");
  const weightByKind = {
    self: 0,
    org: 0,
    external: 0,
    broadcast: 0,
  };
  for (const edge of traffic) {
    if (edge.kind === "self") weightByKind.self += edge.weight;
    else if (edge.kind === "org") weightByKind.org += edge.weight;
    else if (edge.kind === "external") weightByKind.external += edge.weight;
    else if (edge.kind === "broadcast") weightByKind.broadcast += edge.weight;
  }

  const personTouch = new Map<string, number>();
  const bumpPerson = (nodeId: string, w: number) => {
    const uid = userIdFromNode(nodeId) ??
      (nodeId.startsWith("agent:")
        ? agentsById.get(nodeId.slice(6))?.user_id
        : undefined);
    if (!uid) return;
    personTouch.set(uid, (personTouch.get(uid) ?? 0) + w);
  };
  let personToPerson = 0;
  for (const edge of traffic) {
    if (edge.kind === "self") continue;
    personToPerson += edge.weight;
    bumpPerson(edge.from, edge.weight);
    bumpPerson(edge.to, edge.weight);
  }

  let hubUserId: string | null = null;
  let hubWeight = 0;
  for (const [uid, w] of personTouch) {
    if (w > hubWeight) {
      hubUserId = uid;
      hubWeight = w;
    }
  }

  let starTouch = 0;
  if (hubUserId) {
    const hubUser = userNodeId(hubUserId);
    const hubAgents = new Set(
      (agentsByUser.get(hubUserId) ?? []).map((a) => agentNodeId(a.id)),
    );
    const isHub = (id: string) => id === hubUser || hubAgents.has(id);
    for (const edge of traffic) {
      if (edge.kind === "self") continue;
      if (isHub(edge.from) || isHub(edge.to)) starTouch += edge.weight;
    }
  }

  const selfUsers = new Set<string>();
  for (const edge of traffic) {
    if (edge.kind !== "self") continue;
    const a = userIdFromNode(edge.from) ??
      agentsById.get(edge.from.slice(6))?.user_id;
    const b = userIdFromNode(edge.to) ??
      agentsById.get(edge.to.slice(6))?.user_id;
    if (a) selfUsers.add(a);
    if (b) selfUsers.add(b);
  }

  const independentSelfUsers = [...selfUsers].filter((id) => id !== hubUserId)
    .length;

  return {
    nodes,
    edges: [...edges.values()],
    bias: {
      self_weight: weightByKind.self,
      org_weight: weightByKind.org,
      external_weight: weightByKind.external,
      broadcast_weight: weightByKind.broadcast,
      hub_user_id: hubUserId,
      hub_label: hubUserId
        ? (usersById.get(hubUserId)?.handle ?? hubUserId.slice(0, 8)).toLowerCase()
        : null,
      star_share: personToPerson > 0
        ? Math.min(1, starTouch / personToPerson)
        : 0,
      independent_self_users: independentSelfUsers,
    },
  };
}

/** Hub counts for the Phase 1 evidence scoreboard + KV wipe watch. */
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

  const membersByOrg = new Map<string, string[]>();
  const memberIter = kv.list({ prefix: ["org_members"] });
  for await (const entry of memberIter) {
    const orgId = entry.key[1];
    const userId = entry.key[2];
    if (typeof orgId !== "string" || typeof userId !== "string") continue;
    const list = membersByOrg.get(orgId) ?? [];
    list.push(userId);
    membersByOrg.set(orgId, list);
  }

  let orgsWithTwoPlusMembers = 0;
  for (const list of membersByOrg.values()) {
    if (list.length >= 2) orgsWithTwoPlusMembers += 1;
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

  const graph = buildOpsGraph({ orgs, users, agents, threads, membersByOrg });

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
    graph,
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
