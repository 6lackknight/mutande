# mutande hosted MCP (L0 + L2 inbox)

Multi-tenant **remote** MCP server at `https://mcp.mutande.online`.

ChatGPT web / Claude.ai connect **to us** as MCP clients. Identity is Auth0 OAuth 2.1 (same account as Mac / hub). Local sidecar MCP (`core` stdio → daemon) is unchanged.

## Why a separate package (not a hub route)

`directory.prd` §10: L0 is the largest build in the web-agents PRD and is **not** a hub route addition.

| Concern | Hub | This package (`mcp/`) |
|---------|-----|------------------------|
| Role | Blind courier + org/agent store | MCP resource server + OAuth discovery |
| Deploy | Deno Deploy `mutande` → `hub.mutande.online` | Deno Deploy `mutande-mcp` → `mcp.mutande.online` |
| Auth | Validates Auth0 JWT for HTTP API | Same Auth0 tenant; exposes RFC 9728 PRM for MCP clients |
| Agent rows | Source of truth (`transport: mcp` via `POST /v1/agents/connect/mcp`) | Binds session → Auth0 user → hub MCP agent slot |

Shared Auth0 audience (`https://hub.mutande.app`) means L0 can call hub with the user's Bearer token **without** OBO token exchange. A dedicated MCP resource audience + OBO is optional later (see Auth0 config below).

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| GET | `/health` | — |
| GET | `/.well-known/oauth-protected-resource` | — (RFC 9728) |
| GET | `/mcp` | Bearer — opens Streamable HTTP SSE (`text/event-stream`) |
| POST | `/mcp` | Bearer — JSON-RPC (`application/json` responses) |
| DELETE | `/mcp` | Bearer + `Mcp-Session-Id` — end transport session |

Streamable HTTP (MCP 2025-03-26): clients use the same `/mcp` URL for POST messages and optional GET SSE. `initialize` responses include `Mcp-Session-Id`; clients should send that header on later requests. Unauthenticated GET/POST/DELETE never open a stream or return session state.

On each authenticated `/mcp` call the server:

1. Verifies the Auth0 access token (JWKS)
2. `GET {hub}/v1/me` — must be onboarded
3. `POST {hub}/v1/agents/connect/mcp` `{ slug }` — create/refresh MCP agent_id row (hub assigns `transport: mcp`)
4. Handles MCP JSON-RPC (`initialize`, `tools/list`, `tools/call`, `ping`)

Default slug: `chatgpt` (`MCP_DEFAULT_AGENT_SLUG`). Override with `?slug=` or `X-Mutande-Agent-Slug`.

## Tools (L0 + L2)

| Tool | Status |
|------|--------|
| `health` | Implemented — returns bound Auth0 sub, handle, `agent_id` |
| `ping` | Implemented — empty OK (MCP protocol ping; not product E2E ping) |
| `list_threads` | L2 — hub inbox filtered to bound web `agent_id` + `encryption_mode: app_envelope`; `caught_up` when empty |
| `get_thread` | L2 — `GET /v1/threads/:id/app-messages?agent_id=` |
| `reply_to_thread` | L2 — posts `app_envelope` (never E2E seal) |
| `list_agents` | Implemented — `GET /v1/agents` (dual sidecar/mcp slots + `transport`) |
| `list_contacts` | Implemented — org contacts + approved external (`/v1/contacts` + `/external`) |
| `forward_draft` | Implemented — `POST /v1/threads` with `app_envelope` only (ephemeral bundle in args); refuses E2E paths |
| `close_thread` | Implemented — `POST /v1/threads/:id/close` |
| `delete_thread` | Implemented — `DELETE /v1/threads/:id` |
| `upvote_message` | Implemented — `POST /v1/threads/:id/messages/:messageId/upvote` |
| `mark_processed` | N/A — local sidecar bookkeeping only; returns explanatory `na: true` |

New mail from hosted MCP is **app_envelope-only**. If hub would resolve the recipient to an E2E path, `forward_draft` returns a clear refusal and suggests the Mac sidecar.

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

Tests:

```bash
cd mcp && deno task test && deno task check
```

## Deploy

**Live:** `https://mcp.mutande.online` (Deno Deploy project `mutande-mcp`). Redeploy:

1. Env: keep `.env.example` names set on Deploy (`AUTH0_DOMAIN`, `AUTH0_AUDIENCE`, `MUTANDE_HUB_URL`, `MCP_PUBLIC_URL`).
2. Hub: `MCP_ENDPOINT=https://mcp.mutande.online` if not using the built-in default.
3. `cd mcp && deno task deploy`

## Auth0 app / tenant config

**Done in prod** (Resource Parameter Compatibility, domain-level connections, DCR or manual ChatGPT/Claude clients). Reference: [`docs/AUTH0.md`](../docs/AUTH0.md) §8. Summary:

1. **Reuse** API audience `https://hub.mutande.app` (L0 default) so MCP→hub calls work with one token.
2. Tenant **Advanced**: **Resource Parameter Compatibility Profile** and **Include Issuer in Authorization Responses** (MCP client discovery).
3. Promote DB / social connections to **domain-level** so third-party MCP clients (ChatGPT, Claude) can use them.
4. **Dynamic Client Registration** *or* manually register ChatGPT / Claude redirect URIs (see Auth0 “Register your MCP Client Application”).
5. Optional later: separate Auth0 API identifier `https://mcp.mutande.online` + OBO to hub (`AUTH0_MCP_AUDIENCE`).

## ChatGPT / Claude.ai connector setup

1. Finish mutande onboarding (Mac or web) with the same Auth0 account you will use in the host.
2. In ChatGPT (or Claude.ai) → **Settings → Connectors / MCP** → add remote MCP server URL:
   ```
   https://mcp.mutande.online/mcp
   ```
3. Complete the OAuth browser login (Auth0 Universal Login on `auth.mutande.online`).
4. After connect, call tool **`health`** — should show your handle and a web `agent_id`.
5. Call **`list_threads`** — empty/`caught_up` when quiet; otherwise open with **`get_thread`** / **`reply_to_thread`**.

Local Inspector:

```bash
npx @modelcontextprotocol/inspector
# Transport: Streamable HTTP
# URL: http://127.0.0.1:3849/mcp
# Auth: paste an Auth0 access token with audience https://hub.mutande.app
```

curl smoke (replace `$TOKEN`):

```bash
# Unauthorized GET must not open a stream
curl -sI -H 'Accept: text/event-stream' http://127.0.0.1:3849/mcp | head -1
# → HTTP/1.1 401

# SSE stream opens (Ctrl-C to stop; watch `: connected` / `: keepalive`)
curl -N -H "Authorization: Bearer $TOKEN" -H 'Accept: text/event-stream' \
  http://127.0.0.1:3849/mcp

# Initialize → capture Mcp-Session-Id, then tools/call
curl -sD - -o /tmp/mcp-init.json \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"curl","version":"0"}}}' \
  http://127.0.0.1:3849/mcp
```

## Streamable HTTP / SSE notes

- **Done:** GET `/mcp` SSE, POST JSON-RPC, DELETE session, `Mcp-Session-Id` on initialize.
- POST keeps **JSON** responses (allowed by the transport; clients must also Accept `text/event-stream`).
- GET streams stay open with SSE comment keepalives; server→client JSON-RPC on that stream is reserved for future notifications (no hub mail push here).
- Sessions are **in-memory per Deno isolate** — after a cold start, unknown `Mcp-Session-Id` → HTTP 404 and the client must re-`initialize` (per spec).
- **Not this package:** hub `GET /v1/events` mail SSE wake (still deferred).

## Desktop-only / still deferred

Still **Mac sidecar MCP only** (not on hosted MCP):

- `get_router` / `set_router`
- `get_draft` / `draft_add_question` / `draft_add_resource` (local draft store)
- `get_safety_number` / `contact_safety_number` / `verify_contact`
- Product `ping` (health/thread E2E ping)
- `forward_blob` (E2E seal + R2)

Other deferred:

- Hub SSE wake (`GET /v1/events`) for lower-latency inbox
- OBO token exchange when MCP audience ≠ hub audience

Local `core` stdio MCP path is **not** modified by this package (except daemon L2 send/open for app_envelope). See `docs/DIRECTORY-IMPLEMENTATION.md` for L0–L5 status.
