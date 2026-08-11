# mutande hosted MCP

Multi-tenant **remote** MCP at [`https://mcp.mutande.online`](https://mcp.mutande.online).

ChatGPT web / Claude.ai connect **to us** as MCP clients. Identity is Auth0 OAuth 2.1 (same account as Mac / hub). Local sidecar MCP (`core` stdio → daemon) is unchanged.

**End-user connector steps:** [`docs/HOSTED-MCP.md`](../docs/HOSTED-MCP.md) · public site [`/docs/hosted-mcp`](https://mutande.online/docs/hosted-mcp)  
**Auth0 / ops:** [`docs/AUTH0.md`](../docs/AUTH0.md) §8

## Why a separate package (not a hub route)

`directory.prd` §10: L0 is not a hub route addition.

| Concern | Hub | This package (`mcp/`) |
|---------|-----|------------------------|
| Role | Blind courier + org/agent store | MCP resource server + OAuth discovery |
| Deploy | Deno Deploy `mutande` → `hub.mutande.online` | Deno Deploy `mutande-mcp` → `mcp.mutande.online` |
| Auth | Validates Auth0 JWT for HTTP API | Same Auth0 tenant; exposes RFC 9728 PRM for MCP clients |
| Agent rows | Source of truth (`transport: mcp` via `POST /v1/agents/connect/mcp`) | Binds session → Auth0 user → hub MCP agent slot |

Shared Auth0 audiences (`https://hub.mutande.app` + `https://mcp.mutande.online`) mean hosted MCP calls hub with the user's Bearer token **without** OBO. ChatGPT DCR issues the MCP resource as `aud`; set `AUTH0_MCP_AUDIENCE` on **both** mcp and hub. Optional later: OBO only (`AUTH0_MCP_AUDIENCE` on mcp, hub stays hub-aud).

## Connect ChatGPT / Claude.ai

1. Finish mutande onboarding (Mac or web) with the Auth0 account you will use in the host.
2. Add remote MCP connector URL:
   ```
   https://mcp.mutande.online/mcp
   ```
3. Complete OAuth (Auth0 Universal Login on `auth.mutande.online`).
4. Call **`health`** — expect handle + web `agent_id`.
5. Call **`list_threads`** — empty/`caught_up` when quiet; open with **`get_thread`** / **`reply_to_thread`**.

**What works:** app_envelope inbox + compose (`list_threads`, `get_thread`, `reply_to_thread`, `forward_draft`, agents/contacts, close/delete/upvote).  
**Mac sidecar still required:** E2E seal/open, safety numbers, local drafts, product health/thread `ping`, blobs, router.

Hub prod needs **`APP_ENVELOPE_KEY`** (AES-GCM at rest) for app_envelope mail — already set in production.

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| GET | `/health` | — |
| GET | `/.well-known/oauth-protected-resource` | — (RFC 9728) |
| GET | `/mcp` | Bearer — Streamable HTTP SSE (`text/event-stream`) |
| POST | `/mcp` | Bearer — JSON-RPC (`application/json`) |
| DELETE | `/mcp` | Bearer + `Mcp-Session-Id` — end session |

Streamable HTTP (MCP 2025-03-26): same `/mcp` URL for POST and optional GET SSE. `initialize` returns `Mcp-Session-Id`; send it on later requests. Unauthenticated GET/POST/DELETE never open a stream.

On each authenticated `/mcp` call:

1. Verify Auth0 access token (JWKS)
2. `GET {hub}/v1/me` — must be onboarded
3. `POST {hub}/v1/agents/connect/mcp` `{ slug }` — create/refresh MCP agent row (`transport: mcp`)
4. Handle MCP JSON-RPC (`initialize`, `tools/list`, `tools/call`, protocol `ping`)

Default slug: `chatgpt` (`MCP_DEFAULT_AGENT_SLUG`). Override with `?slug=` or `X-Mutande-Agent-Slug`.

## Tools

| Tool | Status |
|------|--------|
| `health` | Bound Auth0 sub, handle, `agent_id` |
| `ping` | MCP protocol ping (empty OK) — **not** product E2E ping |
| `list_threads` | Hub inbox for bound web `agent_id` + `encryption_mode: app_envelope`; `caught_up` when empty |
| `get_thread` | `GET /v1/threads/:id/app-messages?agent_id=` |
| `reply_to_thread` | Posts `app_envelope` (never E2E seal) |
| `list_agents` | `GET /v1/agents` (sidecar/mcp slots + `transport`) |
| `list_contacts` | Org contacts + approved external |
| `forward_draft` | `POST /v1/threads` with **app_envelope only** (ephemeral bundle in args); refuses E2E paths |
| `close_thread` | `POST /v1/threads/:id/close` |
| `delete_thread` | `DELETE /v1/threads/:id` |
| `upvote_message` | `POST /v1/threads/:id/messages/:messageId/upvote` |
| `mark_processed` | **N/A** — sidecar bookkeeping; returns explanatory `na: true` |

New mail from hosted MCP is **app_envelope-only**. If hub would resolve the recipient to E2E, `forward_draft` refuses and points at the Mac sidecar.

**Attaching files from ChatGPT:** put UTF-8 text/markdown in `resources[].content` (or body in `bundle.notes`). Never pass `/mnt/data/…` paths and never base64 text files — this server cannot read the ChatGPT sandbox. Use `content_base64` only for binary (pdf/png), keep under ~1MB. `forward_draft` success returns `thread_id`, `message_id`, `resource_count`, and `resource_names`.

**Dual-slot senders:** hosted MCP always sends `from_agent_id` (bound web slot) so `chatgpt` mcp is not remapped to a preferred sidecar row (that wrongly forced E2E and returned no `thread_id`).

### Redeploy (hub + MCP)

Tool-description / attachment-clarity changes need **MCP only**. Hub+MCP together when changing `from_agent_id` / create-thread wire:

```bash
# Hub (only if hub store/API changed)
cd hub && deployctl deploy --project=mutande

# Hosted MCP — instructions, tool schemas, resource_count on forward_draft
cd mcp && deno task deploy
```

Verify: ChatGPT `forward_draft` to `@cursor` with `resources:[{name, content}]` returns JSON with `thread_id`, `message_id`, `resource_count`, `resource_names`; `list_threads` with `filter: "open"` shows the outbound thread; path-only `/mnt/data/…` is refused.

### Mac sidecar only (not on hosted MCP)

- `get_router` / `set_router`
- `get_draft` / `draft_add_question` / `draft_add_resource`
- `get_safety_number` / `contact_safety_number` / `verify_contact`
- Product `ping` (health / thread E2E)
- `forward_blob` (E2E + R2)

Also deferred elsewhere: hub `GET /v1/events` mail SSE wake; OBO when MCP audience ≠ hub.

## Local dev

```bash
# Terminal A — hub
cd hub && deno task dev

# Terminal B — hosted MCP
cd mcp
cp .env.example .env   # point MUTANDE_HUB_URL at local hub if needed
deno task dev
curl http://127.0.0.1:3849/health
```

```bash
cd mcp && deno task test && deno task check
```

Inspector:

```bash
npx @modelcontextprotocol/inspector
# Transport: Streamable HTTP
# URL: http://127.0.0.1:3849/mcp
# Auth: Auth0 access token, audience https://hub.mutande.app
```

## Error reporting (GlitchTip)

Uses `@sentry/deno` → GlitchTip project **26806** (same pattern as hub). Built-in prod DSN; override with `MUTANDE_SENTRY_DSN` / `SENTRY_DSN`, or set empty to disable. `tracesSampleRate` is `0.01`; request bodies/cookies are stripped. Unexpected route failures go through Hono `onError` → GlitchTip (expected 401/403/bind responses are not reported).

```bash
cd mcp && deno task smoke:sentry   # capture a smoke message, then exit
```

## Redeploy

**Live:** `https://mcp.mutande.online` (Deno Deploy project `mutande-mcp`).

1. Confirm Deploy env matches `.env.example` names: `AUTH0_DOMAIN`, `AUTH0_AUDIENCE`, `AUTH0_MCP_AUDIENCE`, `MUTANDE_HUB_URL`, `MCP_PUBLIC_URL` (optional `MCP_DEFAULT_AGENT_SLUG`). `AUTH0_MCP_AUDIENCE` defaults to `MCP_PUBLIC_URL` when unset; hub defaults to `https://mcp.mutande.online`. GlitchTip DSN for mcp project 26806 is built-in; set `SENTRY_DSN=` (empty) to disable, or override with `MUTANDE_SENTRY_DSN` / `SENTRY_DSN`.
2. Hub: `MCP_ENDPOINT=https://mcp.mutande.online` if not using the built-in default; prod **`APP_ENVELOPE_KEY`** must stay set. **Redeploy hub too** after dual-aud changes (`cd hub && deno task deploy` or your usual hub ship).
3. Ship:
   ```bash
   cd mcp && deno task deploy
   # and hub (same AUTH0_MCP_AUDIENCE default / env)
   ```
4. Smoke: `curl -s https://mcp.mutande.online/health` then reconnect ChatGPT and call `health`.
5. Optional real-token check (Mac Access Token or Auth0 test token with `aud=https://mcp.mutande.online`):
   ```bash
   TOKEN='…' # JWT with aud=https://mcp.mutande.online, iss=https://auth.mutande.online/
   curl -sS -D- https://mcp.mutande.online/mcp \
     -H "Authorization: Bearer $TOKEN" \
     -H 'Content-Type: application/json' \
     -H 'Accept: application/json' \
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"curl","version":"0"}}}'
   # expect HTTP 200 + Mcp-Session-Id (not 401)
   curl -sS https://hub.mutande.online/v1/me -H "Authorization: Bearer $TOKEN"
   # expect 200 onboarded profile (not 401) — proves hub dual-aud
   ```
6. Doctor (no secrets): `./scripts/auth0-mcp-doctor.sh`

**ChatGPT `MCP_ACTION_DISCOVERY_FAILED` / 424 / “Reauthentication required”:** ChatGPT wraps our HTTP 401 after OAuth. Usual cause was rejecting MCP-aud tokens (missing dual-aud on mcp or hub). After redeploy both, remove + re-add the connector.
## Auth0 (operator)

MCP only exposes RFC 9728 PRM → Auth0. **DCR lives on the Auth0 tenant** (`POST https://auth.mutande.online/oidc/register`). If ChatGPT shows `dynamic client registration is disabled`, enable DCR in Auth0 — do not redeploy this package. Full steps + troubleshooting: [`docs/AUTH0.md`](../docs/AUTH0.md) §8 · end-user: [`docs/HOSTED-MCP.md`](../docs/HOSTED-MCP.md).

Short checklist:

1. Create Auth0 API Identifier `https://mcp.mutande.online` (ChatGPT sends that as `resource`); keep hub API `https://hub.mutande.app` for Mac/web.
2. Tenant **Advanced**: Resource Parameter Compatibility + Include Issuer + **DCR** (or CIMD import) + Enable Application Connections.
3. Domain-level DB/social connections for third-party MCP clients.
4. Default third-party permissions on **both** APIs (`https://mcp.mutande.online` and `https://hub.mutande.app`).
5. Deploy `AUTH0_MCP_AUDIENCE=https://mcp.mutande.online` on mcp **and** hub.

## Streamable HTTP notes

- GET `/mcp` SSE, POST JSON-RPC, DELETE session, `Mcp-Session-Id` on initialize — **live**.
- POST keeps JSON responses (clients must also Accept `text/event-stream`).
- GET streams use SSE comment keepalives; server→client JSON-RPC on that stream reserved for future notifications (no hub mail push here).
- Sessions are **in-memory per Deno isolate** — cold start → unknown `Mcp-Session-Id` → HTTP 404 → client re-`initialize`.

Local `core` stdio MCP is not modified by this package (except daemon L2 send/open for app_envelope). Layer status: `docs/DIRECTORY-IMPLEMENTATION.md`.
