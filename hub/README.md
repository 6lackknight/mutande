# Mutande Hub

Blind courier API on Deno Deploy: Hono + Deno KV (+ R2 for blobs in production).

Stores ciphertext envelopes, thread metadata, public keys, and (for `app_envelope` threads) hub-readable application payloads with 30-day retention. Never stores private keys. E2E threads remain a blind courier.

Auth is **Auth0-first**: the hub validates Auth0 access tokens via JWKS. Self-serve onboarding is create-team or join-with-invite.

Tenant / app setup (API, web, Mac, env vars): see [`docs/AUTH0.md`](../docs/AUTH0.md).

**Prod URLs:** hub `https://hub.mutande.online`; web `https://mutande.online` (until `mutande.ai`).

## Local dev

```bash
export AUTH0_DOMAIN=your-tenant.us.auth0.com
export AUTH0_AUDIENCE=https://hub.mutande.app
deno task dev
curl http://localhost:8000/health
```

## Tests

```bash
deno task test
deno task check
```

## API (v1)

| Method | Path | Auth |
|--------|------|------|
| GET | `/health` | — |
| GET | `/v1/me` | Auth0 Bearer |
| GET | `/v1/auth/me` | Auth0 Bearer (alias) |
| POST | `/v1/orgs` | Auth0 Bearer (not yet onboarded) |
| PATCH | `/v1/orgs` | Auth0 Bearer + hub `org_admin` — rename org slug (rewrites live member handles; thread history unchanged) |
| POST | `/v1/onboarding/join` | Auth0 Bearer (not yet onboarded) |
| POST | `/v1/devices` | Auth0 Bearer (onboarded) |
| GET/POST | `/v1/admin/invites` | Auth0 Bearer + hub `org_admin` |
| GET | `/v1/admin/feedback` | Auth0 Bearer + Auth0 role `SuperAdmin` |
| GET | `/v1/admin/waitlist` | Auth0 Bearer + Auth0 role `SuperAdmin` |
| GET | `/v1/admin/census` | Auth0 SuperAdmin — Phase 1 evidence counts + KV wipe watch (no PII) |
| GET | `/v1/admin/registry` | Auth0 SuperAdmin — all registry listings |
| POST | `/v1/admin/registry/:id/verify` | Auth0 SuperAdmin — domain/brand verify + reserve org slug |
| POST | `/v1/admin/registry/:id/publish` | Auth0 SuperAdmin — publish (after verify; SLA target 5 business days) |
| POST | `/v1/admin/registry/:id/suspend` | Auth0 SuperAdmin — immediate suspend (new sends blocked) |
| POST | `/v1/admin/registry/:id/unpublish` | Auth0 SuperAdmin — back to draft |
| POST | `/v1/admin/billing/credits` | Auth0 SuperAdmin — `{ org_id, amount_usd, note? }` ops top-up |
| GET | `/v1/admin/billing/ledger/:orgId` | Auth0 SuperAdmin |
| GET | `/v1/admin/enterprise/metrics` | Auth0 SuperAdmin — no-PII delivery metrics |
| GET | `/v1/registry` | — published listings |
| GET | `/v1/registry/listing/:idOrAddress` | — listing + `trust_tier` warn banner payload |
| GET/POST | `/v1/registry/mine`, `/drafts`, `/billing` | Auth0 Bearer (onboarded) — submitter drafts + ledger |
| POST | `/v1/registry/billing/debit` | Auth0 Bearer — debit-on-store gate (also folded into createThread) |
| POST | `/v1/feedback` | Auth0 Bearer (onboarded) — in-app pilot feedback |
| POST | `/v1/waitlist` | — public marketing waitlist survey |
| GET | `/v1/contacts` | Auth0 Bearer (onboarded) — same-org + broadcast |
| GET | `/v1/contacts/external` | Auth0 Bearer — approved bilateral external contacts (L3) |
| DELETE | `/v1/contacts/external/:linkId` | Auth0 Bearer — unpair |
| POST/GET | `/v1/contacts/pairing/pin` | Auth0 Bearer — issue / read 6-digit PIN (+ QR) |
| POST | `/v1/contacts/pairing/pin/rotate` | Auth0 Bearer — invalidate + re-issue |
| POST | `/v1/contacts/pairing/request` | Auth0 Bearer — `{ handle, pin, intro? }` |
| GET | `/v1/contacts/pairing/pending` | Auth0 Bearer — `{ incoming, outgoing }` |
| POST | `/v1/contacts/pairing/:id/approve` \| `/deny` | Auth0 Bearer — bilateral link or deny |
| GET | `/v1/admin/pairing-flags` | Auth0 SuperAdmin — harassment signals |
| GET/POST | `/v1/agents` | Auth0 Bearer (onboarded); `?handle=` for recipient slug autocomplete |
| GET/PUT | `/v1/agents/router` | Auth0 Bearer — default agent + routing rules |
| PUT | `/v1/agents/default` | Auth0 Bearer — set default agent |
| POST | `/v1/agents/connect/mcp` | Auth0 Bearer — MCP capability handshake; hub assigns `transport: mcp` + `mcp_endpoint` |
| POST | `/v1/agents/connect/sidecar` | Auth0 Bearer — sidecar capability handshake; hub assigns `transport: sidecar` |
| GET/PUT | `/v1/agents/transport-defaults` | Auth0 Bearer — preferred transport per display slug |
| POST | `/v1/agents/web` | Auth0 Bearer — **compat alias** → same as `/connect/mcp` |
| PATCH | `/v1/agents/:agentId` | Auth0 Bearer — rename slug (same `agent_id`) |
| PUT/GET | `/v1/agents/:agentId/handshake` | Auth0 Bearer — intro card (owner PUT; org members + thread peers GET) |
| PUT/GET | `/v1/agents/:agentId/handshake` | Auth0 Bearer — intro card (PUT owner; GET org or thread peer) |
| GET/POST | `/v1/threads` | Auth0 Bearer (onboarded); `POST` accepts `envelope` **or** `app_envelope` (never both) |
| GET | `/v1/threads/:id` | Auth0 Bearer (onboarded); hydrates `app_envelope` when thread mode is non-E2E; may include `pending_downgrade` |
| GET | `/v1/threads/:id/app-messages` | Auth0 Bearer — web/MCP pull of app_envelope content; optional `?agent_id=`; post-downgrade history sealed |
| POST | `/v1/threads/:id/replies` | Auth0 Bearer (onboarded); wire unit must match thread `encryption_mode` |
| GET | `/v1/threads/downgrade-proposals/pending` | Auth0 Bearer — L5 pending downgrade proposals for caller |
| POST | `/v1/threads/:id/downgrade-proposals` | Auth0 Bearer — propose add web agent (`{ agent_slug }`) |
| POST | `/v1/threads/:id/downgrade-proposals/:pid/approve` | Auth0 Bearer — sidecar participant approve |
| POST | `/v1/threads/:id/downgrade-proposals/:pid/deny` | Auth0 Bearer — deny (thread stays E2E) |
| POST | `/v1/threads/:id/close` | Auth0 Bearer (onboarded) |
| CRUD | `/v1/drafts` | Auth0 Bearer (onboarded) |
| POST | `/v1/blobs/upload-url` | Auth0 Bearer (onboarded) |
| POST | `/v1/blobs/:id/download-url` | Auth0 Bearer (onboarded) |

### Auth0 contract (summary)

1. Client sends `Authorization: Bearer <Auth0 access token>`.
2. `GET /v1/me` → `{ auth0_sub, email?, onboarded, needs_onboarding?, user?, org? }`.
3. If not `onboarded`:
   - **Create team:** `POST /v1/orgs` `{ slug, name?, handle? }` → creator becomes `org_admin`; default handle `email-local@slug`.
   - **Join:** `POST /v1/onboarding/join` `{ invite_code, handle? }` → `member`; invite burned.
4. `POST /v1/devices` `{ pubkey, platform }` (`macos` \| `ios` \| `web`).
5. Org admins: `GET/POST /v1/admin/invites` (hub stores codes; email delivery is web-side / Plunk).

Inline envelopes limited to ~60KB serialized. Blobs use R2 presigned PUT/GET when configured; otherwise mock `https://blobs.mutande.app/{id}` URLs with the same response shape. Per-org 500MB quota is tracked in KV.

### Thread encryption mode (L2)

Every thread has `encryption_mode`: `e2e` (blind courier envelopes) or `app_envelope` (hub-readable, 30-day retention). Mode is fixed at creation from participants (§4.2): any web (`transport: mcp`), external, or enterprise participant → `app_envelope`; same-org all-sidecar → `e2e`. Never mix `envelope` and `app_envelope` in one request.

**L5 downgrade:** adding a web agent to an existing E2E thread requires unanimous sidecar-participant approval (`POST /v1/threads/:id/downgrade-proposals`, then `…/approve` or `…/deny`). On approve the mode flips to `app_envelope` for future messages only, `downgrade_point` is set, and a system divider records the end of E2E. Pre-downgrade history stays sealed for the web joiner. Ratchet is one-way — never re-upgrade.

`app_envelope` bodies live under a separate KV prefix (`app_envelopes/…`) with `expireIn` = 30 days. **`APP_ENVELOPE_KEY` is required in prod** (set): base64 32-byte AES key → AES-GCM at rest (hub-held key — not E2E). Unset is local/dev only (plaintext at rest). Thread delete purges app payloads for all participants.

## Env

| Variable | Required | Description |
|----------|----------|-------------|
| `AUTH0_DOMAIN` | prod | Auth0 tenant domain (JWKS issuer host) |
| `AUTH0_AUDIENCE` | prod | Auth0 API audience for access tokens |
| `AUTH0_MCP_AUDIENCE` | hosted MCP | Extra aud `https://mcp.mutande.online` so ChatGPT tokens validate on hub |
| `R2_ACCOUNT_ID` | for real blobs | Cloudflare account id |
| `R2_ACCESS_KEY_ID` | for real blobs | R2 API token access key |
| `R2_SECRET_ACCESS_KEY` | for real blobs | R2 API token secret |
| `R2_BUCKET` | for real blobs | Bucket name |
| `R2_PUBLIC_BASE` | optional | Mock URL base when R2 is unset (default `https://blobs.mutande.app`) |
| `APP_ENVELOPE_KEY` | prod (required; set) | Base64 32-byte AES-256 key for app_envelope at-rest encryption; unset OK for local/dev only |
| `MUTANDE_SENTRY_DSN` / `SENTRY_DSN` | optional | GlitchTip DSN (hub project). Default is built-in; empty disables |
| `SENTRY_SMOKE` | optional | `1` / `true` — capture a smoke message and exit (needs network) |

When any of `R2_ACCOUNT_ID` / `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` / `R2_BUCKET` is missing, the hub logs a clear warning and returns mock upload/download URLs so local tests work without Cloudflare.

## Deploy

1. Copy values from `hub/.env.example` (or a local `hub/.env`) into the Deno Deploy project **Settings → Environment Variables**:
   `AUTH0_DOMAIN`, `AUTH0_AUDIENCE`, plus R2 vars. GlitchTip DSN for hub project 26611 is built-in; set `SENTRY_DSN=` (empty) to disable, or override with `MUTANDE_SENTRY_DSN` / `SENTRY_DSN`.
2. Then:

```bash
cd hub && deno task deploy
```

`deployctl` targets project `mutande`. Do not commit secrets.

**Agent registry:** prod must serve `GET/POST /v1/agents`, `/v1/agents/router`, `/v1/agents/default`, and `PATCH /v1/agents/:agentId` for self-collaboration addressing (`@slug`, bare `@all`, renameable slugs). Redeploy the hub after those routes land locally.

### L4 Enterprise registry + billing

- **Namespace:** ops verify reserves the listing's org slug (`reserved_org_slugs`). Customer `POST /v1/orgs` collides with reserved slugs. An existing customer org slug cannot be verified for a different listing owner (same legal entity only).
- **Debit-on-store:** `EnterpriseStore.planEnterpriseDebit` / `debitEnterpriseOnStore` — folded into `createThread` / `postReply` when sending to a published listing. Insufficient balance → nothing stored. No refunds. Loop guard: 50 billed msgs/day/thread.
- **Warn banner:** `GET /v1/registry/listing/:address` returns `{ listing, warn: { trust_tier: "enterprise", message } }` for Flutter/web.
- **Stubs remaining:** Stripe self-serve top-up (beta); token billing; marketing registry browse page; domain/brand verification is ops-marked stub (no DNS check); mutande rev-share; hub mail SSE wake (`GET /v1/events` — not MCP `GET /mcp`).
