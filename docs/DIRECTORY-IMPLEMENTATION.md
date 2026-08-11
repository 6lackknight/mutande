# Directory PRD — implementation status

Status for `directory.prd` layers **L0–L5** (web agents, app_envelope, external contacts, enterprise registry, thread downgrade). See the PRD for product rules; this doc is a ship checklist.

## Done (L0–L5)

| Layer | What’s in tree |
|---|---|
| **L0** | Hosted MCP at `mcp/` (`mcp.mutande.online`): Auth0 OAuth, session bind via `POST /v1/agents/connect/mcp` |
| **L1** | Dual agent rows (`transport: sidecar \| mcp`); connect handshake; `GET/PUT /v1/agents/transport-defaults`; Flutter transport chip + Settings prefs; daemon/hub clients |
| **L2** | Hub `app_envelope` store (XOR with E2E `envelope`); `encryption_mode` on threads; MCP inbox tools (`list_threads` / `get_thread` / reply); daemon non-E2E send/open; 30-day KV retention |
| **L3** | External contacts PIN pairing + approve/deny/unpair; Contacts UI + `docs/EXTERNAL-CONTACTS.md`; cross-org → `app_envelope` |
| **L4** | `/v1/registry` drafts + public list; ops verify/publish/suspend; debit-on-store in `createThread` / `postReply`; ops Enterprise metrics tab; enterprise warn banner |
| **L5** | Unanimous sidecar downgrade proposals; one-way ratchet + system divider; Flutter consent banner; hub routes under `/v1/threads/.../downgrade-proposals` |

### Canonical paths (keep these)

- Agent connect: **`POST /v1/agents/connect/mcp`** (canonical); `/v1/agents/web` is a short-term alias only
- Wire unit: **exactly one** of `envelope` or `app_envelope` per message — never both
- Enterprise: **debit on store** (plan + atomic apply); insufficient balance → nothing stored
- External contact mail → **`app_envelope`** only
- Downgrade: unanimous approve → `encryption_mode: app_envelope`; no re-upgrade

## Known stubs / deferred

| Item | Notes |
|---|---|
| **Stripe self-serve top-up** | Beta (ops credits only in alpha) |
| **DNS / brand domain verify** | Ops marks verified; no automated DNS check yet |
| **Marketing registry browse** | Hub APIs exist; public marketing browse page not shipped |
| **Hub SSE wake** | MCP pull only; Future row in PRD §10 |
| **Token billing (`per_token`)** | Metrics collected to advise cutover; `per_message` only for now |
| **Hosted MCP extras** | Full Streamable HTTP SSE GET `/mcp`; OBO when MCP audience ≠ hub; some desktop-only tools not mirrored on hosted MCP |
| **`APP_ENVELOPE_KEY`** | Prod should set base64-32 AES key; unset → plaintext-at-rest interim (local/dev) |

Future PRD items (platform JWT attestation, A2A, etc.) remain out of scope.

## Auth0 deploy notes

Hosted MCP Auth0 setup (tenant toggles, audience, client registration, Deno Deploy env): **`docs/AUTH0.md` §8**.

Also: `mcp/README.md`, `hub/README.md` (L4 notes), `hub/.env.example` (`APP_ENVELOPE_KEY`).

## Quick verify

```bash
cd hub && deno task test
cd mcp && deno task test
# core (example): cargo test --lib hub_client::
# app: flutter test test/agent_transport_test.dart
```
