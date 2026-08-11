# Directory PRD — implementation status

Status for `directory.prd` layers **L0–L5** (web agents, app_envelope, external contacts, enterprise registry, thread downgrade). See the PRD for product rules; this doc is a ship checklist.

**Storage backend:** hub persistence today is Deno KV. Postgres migration spec: [`docs/HUB-POSTGRES-PRD.md`](HUB-POSTGRES-PRD.md) (Prisma Postgres + Prisma ORM, fresh-start cutover) — not started in tree yet.

## Done (L0–L5)

| Layer | What’s in tree |
|---|---|
| **L0** | Hosted MCP **live** at [`https://mcp.mutande.online`](https://mcp.mutande.online) (`mcp/`); Auth0 OAuth (Resource Parameter Compatibility + DCR/manual ChatGPT/Claude clients — `docs/AUTH0.md` §8); session bind via `POST /v1/agents/connect/mcp`; Streamable HTTP **GET/POST/DELETE `/mcp`** (SSE transport + JSON-RPC + `Mcp-Session-Id`) — **SSE done** |
| **L1** | Dual agent rows (`transport: sidecar \| mcp`); connect handshake; `GET/PUT /v1/agents/transport-defaults`; Flutter transport chip + Settings prefs; daemon/hub clients |
| **L2** | Hub `app_envelope` store (XOR with E2E `envelope`); `encryption_mode` on threads; MCP inbox tools; daemon non-E2E send/open; 30-day KV retention; **prod `APP_ENVELOPE_KEY` set** (AES-GCM at rest) |
| **L3** | External contacts PIN pairing + approve/deny/unpair; Contacts UI + `docs/EXTERNAL-CONTACTS.md`; cross-org → `app_envelope` |
| **L4** | `/v1/registry` drafts + public list; ops verify/publish/suspend; debit-on-store in `createThread` / `postReply`; ops Enterprise metrics tab; enterprise warn banner |
| **L5** | Unanimous sidecar downgrade proposals; one-way ratchet + system divider; Flutter consent banner; hub routes under `/v1/threads/.../downgrade-proposals` |

### Canonical paths (keep these)

- Agent connect: **`POST /v1/agents/connect/mcp`** (canonical); `/v1/agents/web` is a short-term alias only
- Wire unit: **exactly one** of `envelope` or `app_envelope` per message — never both
- Enterprise: **debit on store** (plan + atomic apply); insufficient balance → nothing stored
- External contact mail → **`app_envelope`** only
- Downgrade: unanimous approve → `encryption_mode: app_envelope`; no re-upgrade

### Hosted MCP — hub-backed tools

Live on `mcp.mutande.online`. End-user connector: [`HOSTED-MCP.md`](HOSTED-MCP.md); package/redeploy: [`mcp/README.md`](../mcp/README.md).

| Tool | Hub backing |
|---|---|
| `health` | Bound Auth0 sub + web `agent_id` |
| `ping` | MCP protocol ping only (not product E2E ping) |
| `list_threads` | Inbox filtered to bound web agent + `app_envelope` |
| `get_thread` | `GET /v1/threads/:id/app-messages?agent_id=` |
| `reply_to_thread` | Posts `app_envelope` |
| `list_agents` | `GET /v1/agents` |
| `list_contacts` | Org contacts + approved external |
| `forward_draft` | `POST /v1/threads` with `app_envelope` only |
| `close_thread` / `delete_thread` | Hub close / delete |
| `upvote_message` | Hub upvote |
| `mark_processed` | N/A explanatory (`na: true`) — sidecar bookkeeping only |

## Known stubs / deferred

| Item | Notes |
|---|---|
| **Stripe self-serve top-up** | Beta (ops credits only in alpha) |
| **DNS / brand domain verify** | Ops marks verified; no automated DNS check yet |
| **Marketing registry browse** | Hub APIs exist; public marketing browse page not shipped |
| **Hub mail SSE wake** | MCP pull only; hub `GET /v1/events` still future — **not** hosted MCP GET `/mcp` (Streamable HTTP SSE is done) |
| **OBO** | Shared hub audience today; OBO when MCP audience ≠ hub |
| **Desktop-only tools** | Not mirrored on hosted MCP: router, draft staging (`get_draft` / `draft_add_*`), safety numbers / `verify_contact`, product `ping`, `forward_blob` — see [`HOSTED-MCP.md`](HOSTED-MCP.md) |
| **Token billing (`per_token`)** | Metrics collected to advise cutover; `per_message` only for now |
| **Polish** | In-memory MCP sessions per isolate (re-`initialize` after cold start); hub→client JSON-RPC notifications on SSE reserved; privacy-copy / ops-access formalization polish vs §4.6 |

Future PRD items (platform JWT attestation, A2A, etc.) remain out of scope.

## Auth0 / hosted MCP (prod)

Done in production:

1. Auth0 for hosted MCP (Resource Parameter Compatibility, DCR or manual ChatGPT/Claude clients) — **`docs/AUTH0.md` §8**
2. Deploy `mcp/` → **`https://mcp.mutande.online`** (live; Streamable HTTP SSE)
3. Prod **`APP_ENVELOPE_KEY`** set (AES-GCM at rest)

**Connect (users):** [`HOSTED-MCP.md`](HOSTED-MCP.md)  
**Ops / redeploy:** [`mcp/README.md`](../mcp/README.md), `hub/README.md`, `hub/.env.example` (`APP_ENVELOPE_KEY` required in prod; unset OK for local/dev).

## Quick verify

```bash
cd hub && deno task test
cd mcp && deno task test
# core (example): cargo test --lib hub_client::
# app: flutter test test/agent_transport_test.dart
```
