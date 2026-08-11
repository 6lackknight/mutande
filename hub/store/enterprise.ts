/**
 * L4 Enterprise registry + billing foundation (directory.prd §§7.2, 8, 9, 10 L4, 13).
 *
 * Debit-on-store: call `debitEnterpriseOnStore` immediately before committing an
 * `app_envelope` destined for a public enterprise listing. When L2
 * `storeAppEnvelope` lands, invoke it inside that store path (same transaction
 * boundary if possible). Until then this is the clear billing gate interface.
 *
 * Namespace: verified enterprise org slugs are reserved in KV under
 * `reserved_org_slugs`. Customer `createOrg` must call `assertOrgSlugAvailable`.
 */
import {
  conflict,
  forbidden,
  HubError,
  notFound,
} from "./errors.ts";
import { isPlatformOpsAdmin } from "./platform_admin.ts";
import type {
  Agent,
  AgentCapabilities,
  AuthContext,
  BillingLedger,
  BillingLedgerEntry,
  CreateRegistryDraftInput,
  EnterpriseDebitOnStoreInput,
  EnterpriseDebitOnStoreResult,
  EnterpriseDeliveryMetric,
  RegistryListing,
  RegistryListingBilling,
  ReservedOrgSlug,
  TopUpCreditsInput,
  UpdateRegistryDraftInput,
} from "./types.ts";
import {
  ENTERPRISE_BILLED_MSGS_PER_DAY_THREAD,
  ENTERPRISE_WARN_BANNER,
  MCP_ENDPOINT_DEFAULT,
} from "./types.ts";
import { assertValidAgentSlug, parseDisplayAddress } from "./address.ts";

function nowIso(): string {
  return new Date().toISOString();
}

function assertValidOrgSlug(slug: string): void {
  if (!/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(slug)) {
    throw new HubError(
      "Org slug must be lowercase alphanumeric (hyphens allowed)",
      "invalid_slug",
    );
  }
}

/** Parse USD decimal → cents. Rejects negatives and >2 fractional digits. */
export function parseUsdToCents(raw: string): number {
  const s = raw.trim();
  if (!/^\d+(\.\d{1,2})?$/.test(s)) {
    throw new HubError(
      "amount_usd must be a non-negative USD decimal (max 2 places)",
      "invalid_argument",
      400,
    );
  }
  const [whole, frac = ""] = s.split(".");
  const cents = Number(whole) * 100 + Number((frac + "00").slice(0, 2));
  if (!Number.isFinite(cents) || cents < 0) {
    throw new HubError("invalid USD amount", "invalid_argument", 400);
  }
  return cents;
}

export function formatCentsUsd(cents: number): string {
  return (cents / 100).toFixed(2);
}

/** Rough token estimate for metrics until real tokenizer (§9.4 advisory). */
export function estimateTokensFromBytes(payloadBytes: number): number {
  if (payloadBytes <= 0) return 0;
  return Math.max(1, Math.ceil(payloadBytes / 4));
}

function utcDayKey(d = new Date()): string {
  return d.toISOString().slice(0, 10);
}

function normalizeCapabilities(
  input?: AgentCapabilities,
): AgentCapabilities {
  if (!input || typeof input !== "object") return {};
  const out: AgentCapabilities = {};
  if (Array.isArray(input.models)) {
    out.models = input.models.filter((m): m is string => typeof m === "string");
  }
  if (typeof input.default_model === "string") {
    out.default_model = input.default_model.trim();
  }
  if (Array.isArray(input.modalities)) {
    out.modalities = input.modalities.filter((m): m is string =>
      typeof m === "string"
    );
  }
  if (Array.isArray(input.message_types)) {
    out.message_types = input.message_types.filter((m): m is string =>
      typeof m === "string"
    );
  }
  return out;
}

function parseEnterpriseAddress(address: string): {
  local: string;
  orgSlug: string;
  display: string;
} {
  const trimmed = address.trim().toLowerCase();
  const parsed = parseDisplayAddress(trimmed);
  if (parsed.kind !== "user" || parsed.agentSlug) {
    throw new HubError(
      "Enterprise address must be local@org (e.g. assistant@openai)",
      "invalid_address",
      400,
    );
  }
  assertValidAgentSlug(parsed.local); // local part uses agent-slug charset
  assertValidOrgSlug(parsed.orgSlug);
  return {
    local: parsed.local,
    orgSlug: parsed.orgSlug,
    display: `${parsed.local}@${parsed.orgSlug}`,
  };
}

function requireOps(auth: AuthContext): void {
  if (!isPlatformOpsAdmin(auth.auth0Roles)) {
    throw forbidden("Platform admin required");
  }
}

function listingBilling(priceUsd: string): RegistryListingBilling {
  parseUsdToCents(priceUsd); // validate
  return {
    methods: ["per_message"],
    price_usd: formatCentsUsd(parseUsdToCents(priceUsd)),
    currency: "USD",
  };
}

function publicListingView(listing: RegistryListing): RegistryListing {
  return {
    ...listing,
    trust_tier: "enterprise",
    visibility: listing.status === "published" ? "public" : "private",
  };
}

export class EnterpriseStore {
  constructor(private readonly kv: Deno.Kv) {}

  private listingKey(id: string) {
    return ["registry_listings", id];
  }
  private listingAddressKey(address: string) {
    return ["registry_listing_addresses", address];
  }
  private listingsPrefix() {
    return ["registry_listings"];
  }
  private orgListingsKey(orgId: string, listingId: string) {
    return ["org_registry_listings", orgId, listingId];
  }
  private orgListingsPrefix(orgId: string) {
    return ["org_registry_listings", orgId];
  }
  private reservedSlugKey(slug: string) {
    return ["reserved_org_slugs", slug];
  }
  private orgSlugKey(slug: string) {
    return ["org_slugs", slug];
  }
  private agentKey(id: string) {
    return ["agents", id];
  }
  private ledgerKey(orgId: string) {
    return ["billing_ledgers", orgId];
  }
  private ledgerEntryKey(orgId: string, createdAt: string, id: string) {
    return ["billing_ledger_entries", orgId, createdAt, id];
  }
  private ledgerEntriesPrefix(orgId: string) {
    return ["billing_ledger_entries", orgId];
  }
  private loopGuardKey(threadId: string, day: string) {
    return ["enterprise_loop_guard", threadId, day];
  }
  private metricKey(createdAt: string, id: string) {
    return ["enterprise_metrics", createdAt, id];
  }
  private metricsPrefix() {
    return ["enterprise_metrics"];
  }
  private enterpriseThreadKey(threadId: string) {
    return ["enterprise_threads", threadId];
  }

  /** Customer org create must call this before claiming a slug (§8.3 / §13). */
  async assertOrgSlugAvailable(slug: string): Promise<void> {
    const normalized = slug.trim().toLowerCase();
    const reserved = await this.kv.get<ReservedOrgSlug>(
      this.reservedSlugKey(normalized),
    );
    if (reserved.value) {
      throw conflict(
        `Org slug '${normalized}' is reserved for a verified enterprise namespace`,
      );
    }
  }

  async getReservedOrgSlug(slug: string): Promise<ReservedOrgSlug | null> {
    const res = await this.kv.get<ReservedOrgSlug>(
      this.reservedSlugKey(slug.trim().toLowerCase()),
    );
    return res.value ?? null;
  }

  async getListing(id: string): Promise<RegistryListing | null> {
    const res = await this.kv.get<RegistryListing>(this.listingKey(id));
    return res.value ? publicListingView(res.value) : null;
  }

  async getListingByAddress(address: string): Promise<RegistryListing | null> {
    const normalized = address.trim().toLowerCase();
    const idRes = await this.kv.get<string>(this.listingAddressKey(normalized));
    if (!idRes.value) return null;
    return this.getListing(idRes.value);
  }

  /**
   * Resolve a published public enterprise listing for routing (§7.2).
   * Returns null when not published (callers treat as deny / not found).
   */
  async resolvePublishedEnterprise(
    address: string,
  ): Promise<RegistryListing | null> {
    const listing = await this.getListingByAddress(address);
    if (!listing || listing.status !== "published") return null;
    return listing;
  }

  async createDraft(
    auth: AuthContext,
    input: CreateRegistryDraftInput,
  ): Promise<RegistryListing> {
    const { display, orgSlug, local } = parseEnterpriseAddress(input.address);
    const billing = listingBilling(input.price_usd);
    const existing = await this.kv.get<string>(this.listingAddressKey(display));
    if (existing.value) {
      throw conflict(`Registry address '${display}' already exists`);
    }

    const now = nowIso();
    const agentId = crypto.randomUUID();
    const listingId = crypto.randomUUID();
    const agent: Agent = {
      id: agentId,
      user_id: auth.userId,
      slug: local,
      created_at: now,
      transport: "mcp",
      visibility: "private",
      trust_tier: "enterprise",
      billing: {
        methods: ["per_message"],
        price_usd: billing.price_usd,
        currency: "USD",
      },
      mcp_endpoint: MCP_ENDPOINT_DEFAULT,
      capabilities: normalizeCapabilities(input.capabilities),
      capabilities_updated_at: now,
    };

    const listing: RegistryListing = {
      id: listingId,
      address: display,
      agent_id: agentId,
      org_id: auth.orgId,
      submitter_user_id: auth.userId,
      status: "draft",
      trust_tier: "enterprise",
      visibility: "private",
      capabilities: agent.capabilities ?? {},
      billing,
      domain_verified: false,
      reserved_org_slug: null,
      created_at: now,
      updated_at: now,
    };

    // Track intended namespace on draft (not reserved until ops verifies).
    void orgSlug;

    const tx = this.kv.atomic();
    tx.check(existing);
    tx.set(this.listingKey(listingId), listing);
    tx.set(this.listingAddressKey(display), listingId);
    tx.set(this.orgListingsKey(auth.orgId, listingId), listingId);
    tx.set(this.agentKey(agentId), agent);
    const res = await tx.commit();
    if (!res.ok) throw conflict(`Registry address '${display}' already exists`);
    return publicListingView(listing);
  }

  async updateDraft(
    auth: AuthContext,
    listingId: string,
    input: UpdateRegistryDraftInput,
  ): Promise<RegistryListing> {
    const listing = await this.requireListing(listingId);
    this.assertSubmitter(auth, listing);
    if (listing.status !== "draft") {
      throw new HubError(
        "Only draft listings can be edited by the submitter",
        "invalid_state",
        400,
      );
    }
    const billing = input.price_usd !== undefined
      ? listingBilling(input.price_usd)
      : listing.billing;
    const capabilities = input.capabilities !== undefined
      ? normalizeCapabilities(input.capabilities)
      : listing.capabilities;
    const updated: RegistryListing = {
      ...listing,
      billing,
      capabilities,
      updated_at: nowIso(),
    };
    const agent = await this.kv.get<Agent>(this.agentKey(listing.agent_id));
    const tx = this.kv.atomic();
    tx.set(this.listingKey(listingId), updated);
    if (agent.value) {
      tx.set(this.agentKey(listing.agent_id), {
        ...agent.value,
        capabilities,
        billing: {
          methods: ["per_message"],
          price_usd: billing.price_usd,
          currency: "USD",
        },
        capabilities_updated_at: nowIso(),
      });
    }
    await tx.commit();
    return publicListingView(updated);
  }

  /** Submitter-only list of own drafts + published/suspended. */
  async listMine(auth: AuthContext): Promise<{ listings: RegistryListing[] }> {
    const listings: RegistryListing[] = [];
    const iter = this.kv.list<string>({
      prefix: this.orgListingsPrefix(auth.orgId),
    });
    for await (const entry of iter) {
      if (!entry.value) continue;
      const listing = await this.getListing(entry.value);
      if (listing) listings.push(listing);
    }
    listings.sort((a, b) => b.updated_at.localeCompare(a.updated_at));
    return { listings };
  }

  /** Public published directory (no drafts). */
  async listPublished(): Promise<{ listings: RegistryListing[] }> {
    const listings: RegistryListing[] = [];
    const iter = this.kv.list<RegistryListing>({ prefix: this.listingsPrefix() });
    for await (const entry of iter) {
      if (entry.value?.status === "published") {
        listings.push(publicListingView(entry.value));
      }
    }
    listings.sort((a, b) => a.address.localeCompare(b.address));
    return { listings };
  }

  async listAllForOps(
    auth: AuthContext,
  ): Promise<{ listings: RegistryListing[] }> {
    requireOps(auth);
    const listings: RegistryListing[] = [];
    const iter = this.kv.list<RegistryListing>({ prefix: this.listingsPrefix() });
    for await (const entry of iter) {
      if (entry.value) listings.push(publicListingView(entry.value));
    }
    listings.sort((a, b) => b.updated_at.localeCompare(a.updated_at));
    return { listings };
  }

  /**
   * Domain/brand verification stub (§8.3): ops marks verified and reserves
   * the enterprise org slug. Existing customer org with that slug is only
   * allowed when it is the listing owner's org (same legal entity).
   */
  async verifyAndReserveSlug(
    auth: AuthContext,
    listingId: string,
    orgSlug?: string,
  ): Promise<RegistryListing> {
    requireOps(auth);
    const listing = await this.requireListing(listingId);
    const { orgSlug: addressSlug } = parseEnterpriseAddress(listing.address);
    const slug = (orgSlug ?? addressSlug).trim().toLowerCase();
    assertValidOrgSlug(slug);

    const existingOrg = await this.kv.get<{ id: string; slug: string }>(
      this.orgSlugKey(slug),
    );
    if (existingOrg.value && existingOrg.value.id !== listing.org_id) {
      throw conflict(
        `Org slug '${slug}' belongs to an existing customer org; verify the same legal entity before listing`,
      );
    }

    const reservedCheck = await this.kv.get<ReservedOrgSlug>(
      this.reservedSlugKey(slug),
    );
    if (
      reservedCheck.value &&
      reservedCheck.value.listing_id !== listing.id
    ) {
      throw conflict(`Org slug '${slug}' is already reserved`);
    }

    const reserved: ReservedOrgSlug = {
      slug,
      listing_id: listing.id,
      reserved_at: nowIso(),
      org_id: listing.org_id,
    };
    const updated: RegistryListing = {
      ...listing,
      domain_verified: true,
      reserved_org_slug: slug,
      updated_at: nowIso(),
    };
    const tx = this.kv.atomic();
    tx.set(this.listingKey(listing.id), updated);
    tx.set(this.reservedSlugKey(slug), reserved);
    await tx.commit();
    return publicListingView(updated);
  }

  /** Ops publish within SLA target (§8.3 / §13). Requires verification. */
  async publishListing(
    auth: AuthContext,
    listingId: string,
  ): Promise<RegistryListing> {
    requireOps(auth);
    const listing = await this.requireListing(listingId);
    if (listing.status === "published") return publicListingView(listing);
    if (listing.status === "suspended") {
      throw new HubError(
        "Suspended listings must be re-verified before publish; use unsuspend path",
        "invalid_state",
        400,
      );
    }
    if (!listing.domain_verified || !listing.reserved_org_slug) {
      throw new HubError(
        "Domain/brand verification required before publish",
        "verification_required",
        400,
      );
    }
    const now = nowIso();
    const updated: RegistryListing = {
      ...listing,
      status: "published",
      visibility: "public",
      published_at: now,
      updated_at: now,
      suspended_at: undefined,
    };
    const agent = await this.kv.get<Agent>(this.agentKey(listing.agent_id));
    const tx = this.kv.atomic();
    tx.set(this.listingKey(listing.id), updated);
    if (agent.value) {
      tx.set(this.agentKey(listing.agent_id), {
        ...agent.value,
        visibility: "public",
        trust_tier: "enterprise",
        billing: {
          methods: ["per_message"],
          price_usd: listing.billing.price_usd,
          currency: "USD",
        },
      });
    }
    await tx.commit();
    return publicListingView(updated);
  }

  /** Immediate suspend — new sends blocked; in-flight threads stay readable. */
  async suspendListing(
    auth: AuthContext,
    listingId: string,
  ): Promise<RegistryListing> {
    requireOps(auth);
    const listing = await this.requireListing(listingId);
    const now = nowIso();
    const updated: RegistryListing = {
      ...listing,
      status: "suspended",
      visibility: "private",
      suspended_at: now,
      updated_at: now,
    };
    const agent = await this.kv.get<Agent>(this.agentKey(listing.agent_id));
    const tx = this.kv.atomic();
    tx.set(this.listingKey(listing.id), updated);
    if (agent.value) {
      tx.set(this.agentKey(listing.agent_id), {
        ...agent.value,
        visibility: "private",
      });
    }
    await tx.commit();
    return publicListingView(updated);
  }

  /** Ops unpublish (back to draft) without suspending. */
  async unpublishListing(
    auth: AuthContext,
    listingId: string,
  ): Promise<RegistryListing> {
    requireOps(auth);
    const listing = await this.requireListing(listingId);
    const updated: RegistryListing = {
      ...listing,
      status: "draft",
      visibility: "private",
      updated_at: nowIso(),
      published_at: undefined,
      suspended_at: undefined,
    };
    const agent = await this.kv.get<Agent>(this.agentKey(listing.agent_id));
    const tx = this.kv.atomic();
    tx.set(this.listingKey(listing.id), updated);
    if (agent.value) {
      tx.set(this.agentKey(listing.agent_id), {
        ...agent.value,
        visibility: "private",
      });
    }
    await tx.commit();
    return publicListingView(updated);
  }

  async getLedger(orgId: string): Promise<BillingLedger> {
    const res = await this.kv.get<BillingLedger>(this.ledgerKey(orgId));
    if (res.value) return res.value;
    return { org_id: orgId, balance_cents: 0, updated_at: nowIso() };
  }

  async getLedgerForAuth(auth: AuthContext): Promise<BillingLedger> {
    return this.getLedger(auth.orgId);
  }

  async topUpCredits(
    auth: AuthContext,
    input: TopUpCreditsInput,
  ): Promise<{ ledger: BillingLedger; entry: BillingLedgerEntry }> {
    requireOps(auth);
    const amount = parseUsdToCents(input.amount_usd);
    if (amount <= 0) {
      throw new HubError("amount_usd must be positive", "invalid_argument", 400);
    }
    const orgId = input.org_id.trim();
    if (!orgId) {
      throw new HubError("org_id is required", "invalid_argument", 400);
    }

    for (let attempt = 0; attempt < 8; attempt++) {
      const ledgerRes = await this.kv.get<BillingLedger>(this.ledgerKey(orgId));
      const current = ledgerRes.value ?? {
        org_id: orgId,
        balance_cents: 0,
        updated_at: nowIso(),
      };
      const balance = current.balance_cents + amount;
      const now = nowIso();
      const entry: BillingLedgerEntry = {
        id: crypto.randomUUID(),
        org_id: orgId,
        kind: "credit",
        amount_cents: amount,
        balance_after_cents: balance,
        note: input.note?.trim().slice(0, 200) || undefined,
        created_at: now,
        actor_id: auth.auth0Sub,
      };
      const ledger: BillingLedger = {
        org_id: orgId,
        balance_cents: balance,
        updated_at: now,
      };
      const tx = this.kv.atomic();
      tx.check(ledgerRes);
      tx.set(this.ledgerKey(orgId), ledger);
      tx.set(this.ledgerEntryKey(orgId, now, entry.id), entry);
      const res = await tx.commit();
      if (res.ok) return { ledger, entry };
    }
    throw new HubError("Failed to top up credits", "internal", 500);
  }

  /**
   * Routing gate (§7.2): public enterprise send allowed if listing published
   * and sender org has sufficient balance. No contact required.
   */
  async assertEnterpriseSendAllowed(
    auth: AuthContext,
    address: string,
  ): Promise<RegistryListing> {
    const listing = await this.resolvePublishedEnterprise(address);
    if (!listing) {
      throw notFound("Enterprise listing");
    }
    const price = parseUsdToCents(listing.billing.price_usd);
    const ledger = await this.getLedger(auth.orgId);
    if (ledger.balance_cents < price) {
      throw new HubError(
        `Insufficient enterprise credits (need $${listing.billing.price_usd}, have $${formatCentsUsd(ledger.balance_cents)})`,
        "insufficient_balance",
        402,
      );
    }
    return listing;
  }

  /** Find listing owned by this org for a given enterprise agent_id. */
  async findListingByAgentId(agentId: string): Promise<RegistryListing | null> {
    const listings = await this.listPublished();
    const hit = listings.listings.find((l) => l.agent_id === agentId);
    if (hit) return hit;
    // Drafts/suspended also bind agent_id (owner-side).
    const iter = this.kv.list<RegistryListing>({ prefix: this.listingsPrefix() });
    for await (const entry of iter) {
      if (entry.value?.agent_id === agentId) {
        return publicListingView(entry.value);
      }
    }
    return null;
  }

  /**
   * Enterprise agents reply only within billed threads — no new outbound (§7.3 / §12).
   * Call when the sending agent_id belongs to a registry listing.
   */
  async assertEnterpriseAgentSend(
    agentId: string,
    opts: { thread_id?: string; is_new_thread: boolean },
  ): Promise<void> {
    const listing = await this.findListingByAgentId(agentId);
    if (!listing) return;
    if (opts.is_new_thread || !opts.thread_id) {
      throw new HubError(
        "Enterprise agents may only reply within existing billed threads",
        "enterprise_outbound_denied",
        403,
      );
    }
    const threadMeta = await this.kv.get<{ listing_id?: string }>(
      this.enterpriseThreadKey(opts.thread_id),
    );
    if (!threadMeta.value?.listing_id || threadMeta.value.listing_id !== listing.id) {
      throw new HubError(
        "Enterprise agents may only reply within existing billed threads",
        "enterprise_outbound_denied",
        403,
      );
    }
  }

  /**
   * Plan a debit for inclusion in an external atomic (e.g. L2 app_envelope store).
   * Validates balance + loop guard; `apply(tx)` adds checks/sets. Callers must
   * not store the envelope unless the combined tx commits.
   */
  async planEnterpriseDebit(
    auth: AuthContext,
    input: EnterpriseDebitOnStoreInput,
  ): Promise<{
    listing: RegistryListing;
    apply: (tx: Deno.AtomicOperation) => EnterpriseDebitOnStoreResult;
  }> {
    const listing = await this.resolveListingForDebit(input);
    if (listing.status !== "published") {
      throw new HubError(
        "Enterprise listing is not accepting messages",
        "listing_unavailable",
        403,
      );
    }
    const threadId = input.thread_id?.trim();
    if (!threadId) {
      throw new HubError("thread_id is required", "invalid_argument", 400);
    }
    const price = parseUsdToCents(listing.billing.price_usd);
    const day = utcDayKey();
    const payloadBytes = Math.max(0, Math.floor(input.payload_bytes || 0));
    const estimatedTokens = input.estimated_tokens !== undefined
      ? Math.max(0, Math.floor(input.estimated_tokens))
      : estimateTokensFromBytes(payloadBytes);
    const blobCount = Math.max(0, Math.floor(input.blob_count ?? 0));
    const latencyMs = Math.max(0, Math.floor(input.latency_ms ?? 0));

    const ledgerRes = await this.kv.get<BillingLedger>(
      this.ledgerKey(auth.orgId),
    );
    const current = ledgerRes.value ?? {
      org_id: auth.orgId,
      balance_cents: 0,
      updated_at: nowIso(),
    };
    if (current.balance_cents < price) {
      throw new HubError(
        `Insufficient enterprise credits (need $${listing.billing.price_usd}, have $${formatCentsUsd(current.balance_cents)})`,
        "insufficient_balance",
        402,
      );
    }

    const loopRes = await this.kv.get<number>(
      this.loopGuardKey(threadId, day),
    );
    const loopCount = loopRes.value ?? 0;
    if (loopCount >= ENTERPRISE_BILLED_MSGS_PER_DAY_THREAD) {
      throw new HubError(
        `Enterprise loop guard: max ${ENTERPRISE_BILLED_MSGS_PER_DAY_THREAD} billed messages per thread per day`,
        "loop_guard",
        429,
      );
    }

    return {
      listing,
      apply: (tx: Deno.AtomicOperation) => {
        const now = nowIso();
        const balance = current.balance_cents - price;
        const entry: BillingLedgerEntry = {
          id: crypto.randomUUID(),
          org_id: auth.orgId,
          kind: "debit",
          amount_cents: price,
          balance_after_cents: balance,
          listing_id: listing.id,
          thread_id: threadId,
          created_at: now,
          actor_id: auth.userId,
        };
        const ledger: BillingLedger = {
          org_id: auth.orgId,
          balance_cents: balance,
          updated_at: now,
        };
        const metric: EnterpriseDeliveryMetric = {
          id: crypto.randomUUID(),
          created_at: now,
          listing_id: listing.id,
          sender_org_id: auth.orgId,
          payload_bytes: payloadBytes,
          estimated_tokens: estimatedTokens,
          blob_count: blobCount,
          latency_ms: latencyMs,
          price_cents: price,
        };
        tx.check(ledgerRes);
        tx.check(loopRes);
        tx.set(this.ledgerKey(auth.orgId), ledger);
        tx.set(this.ledgerEntryKey(auth.orgId, now, entry.id), entry);
        tx.set(this.loopGuardKey(threadId, day), loopCount + 1);
        tx.set(this.metricKey(now, metric.id), metric);
        tx.set(this.enterpriseThreadKey(threadId), {
          listing_id: listing.id,
          sender_org_id: auth.orgId,
          updated_at: now,
        });
        return { listing, entry, metric, balance_cents: balance };
      },
    };
  }

  /**
   * Debit at app_envelope store time — final, no refunds (§9.3).
   * Standalone commit when not folded into L2 store tx. Prefer
   * `planEnterpriseDebit` + shared atomic with the envelope write.
   */
  async debitEnterpriseOnStore(
    auth: AuthContext,
    input: EnterpriseDebitOnStoreInput,
  ): Promise<EnterpriseDebitOnStoreResult> {
    for (let attempt = 0; attempt < 8; attempt++) {
      const plan = await this.planEnterpriseDebit(auth, input);
      const tx = this.kv.atomic();
      const result = plan.apply(tx);
      const res = await tx.commit();
      if (res.ok) return result;
    }
    throw new HubError("Failed to debit enterprise credits", "internal", 500);
  }

  async listMetrics(
    auth: AuthContext,
    opts?: { limit?: number },
  ): Promise<{ metrics: EnterpriseDeliveryMetric[] }> {
    requireOps(auth);
    const limit = Math.min(Math.max(opts?.limit ?? 200, 1), 1000);
    const items: EnterpriseDeliveryMetric[] = [];
    const iter = this.kv.list<EnterpriseDeliveryMetric>({
      prefix: this.metricsPrefix(),
    }, { reverse: true });
    for await (const entry of iter) {
      if (entry.value) items.push(entry.value);
      if (items.length >= limit) break;
    }
    return { metrics: items };
  }

  /** Listing detail for warn banner + billing display. */
  async getListingPublic(addressOrId: string): Promise<{
    listing: RegistryListing;
    warn: typeof ENTERPRISE_WARN_BANNER;
  }> {
    let listing = await this.getListing(addressOrId);
    if (!listing) listing = await this.getListingByAddress(addressOrId);
    if (!listing || listing.status !== "published") {
      throw notFound("Enterprise listing");
    }
    return { listing, warn: ENTERPRISE_WARN_BANNER };
  }

  private async resolveListingForDebit(
    input: EnterpriseDebitOnStoreInput,
  ): Promise<RegistryListing> {
    if (input.listing_id?.trim()) {
      const listing = await this.getListing(input.listing_id.trim());
      if (!listing) throw notFound("Enterprise listing");
      return listing;
    }
    if (input.address?.trim()) {
      const listing = await this.getListingByAddress(input.address.trim());
      if (!listing) throw notFound("Enterprise listing");
      return listing;
    }
    throw new HubError(
      "listing_id or address is required",
      "invalid_argument",
      400,
    );
  }

  private async requireListing(id: string): Promise<RegistryListing> {
    const listing = await this.getListing(id);
    if (!listing) throw notFound("Enterprise listing");
    return listing;
  }

  private assertSubmitter(auth: AuthContext, listing: RegistryListing): void {
    // Org members of the submitter org may manage drafts for that org.
    if (listing.org_id !== auth.orgId) {
      throw forbidden("Not the listing submitter");
    }
  }
}
