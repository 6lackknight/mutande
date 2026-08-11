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

Shared Auth0 audience (`https://hub.mutande.app`) means hosted MCP calls hub with the user's Bearer token **without** OBO. Optional later: dedicated MCP audience + OBO (`AUTH0_MCP_AUDIENCE`).

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

## Redeploy

**Live:** `https://mcp.mutande.online` (Deno Deploy project `mutande-mcp`).

1. Confirm Deploy env matches `.env.example` names: `AUTH0_DOMAIN`, `AUTH0_AUDIENCE`, `MUTANDE_HUB_URL`, `MCP_PUBLIC_URL` (optional `MCP_DEFAULT_AGENT_SLUG`, `AUTH0_MCP_AUDIENCE`).
2. Hub: `MCP_ENDPOINT=https://mcp.mutande.online` if not using the built-in default; prod **`APP_ENVELOPE_KEY`** must stay set.
3. Ship:
   ```bash
   cd mcp && deno task deploy
   ```
4. Smoke: `curl -s https://mcp.mutande.online/health` then reconnect a host and call `health`.

## Auth0 (prod configured)

Resource Parameter Compatibility, domain-level connections, and DCR or manual ChatGPT/Claude clients are **done in prod**. Operator reference: [`docs/AUTH0.md`](../docs/AUTH0.md) §8. Short checklist:

1. Reuse API audience `https://hub.mutande.app` so MCP→hub uses one token.
2. Tenant **Advanced**: Resource Parameter Compatibility + Include Issuer in Authorization Responses.
3. Domain-level DB/social connections for third-party MCP clients.
4. DCR **or** manually register host redirect URIs.
5. Optional later: API `https://mcp.mutande.online` + OBO (`AUTH0_MCP_AUDIENCE`).

## Streamable HTTP notes

- GET `/mcp` SSE, POST JSON-RPC, DELETE session, `Mcp-Session-Id` on initialize — **live**.
- POST keeps JSON responses (clients must also Accept `text/event-stream`).
- GET streams use SSE comment keepalives; server→client JSON-RPC on that stream reserved for future notifications (no hub mail push here).
- Sessions are **in-memory per Deno isolate** — cold start → unknown `Mcp-Session-Id` → HTTP 404 → client re-`initialize`.

Local `core` stdio MCP is not modified by this package (except daemon L2 send/open for app_envelope). Layer status: `docs/DIRECTORY-IMPLEMENTATION.md`.
