# mutande hosted MCP (L0)

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
| POST | `/mcp` | `Authorization: Bearer <Auth0 access token>` |

On each authenticated `/mcp` call the server:

1. Verifies the Auth0 access token (JWKS)
2. `GET {hub}/v1/me` — must be onboarded
3. `POST {hub}/v1/agents/connect/mcp` `{ slug }` — create/refresh MCP agent_id row (hub assigns `transport: mcp`)
4. Handles MCP JSON-RPC (`initialize`, `tools/list`, `tools/call`, `ping`)

Default slug: `chatgpt` (`MCP_DEFAULT_AGENT_SLUG`). Override with `?slug=` or `X-Mutande-Agent-Slug`.

## Tools (L0)

| Tool | Status |
|------|--------|
| `health` | Implemented — returns bound Auth0 sub, handle, `agent_id` |
| `ping` | Implemented — empty OK |
| `list_threads`, `get_thread`, `reply_to_thread`, … | Stub — clear “not implemented” until L2 `app_envelope` pull |

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

1. Create Deno Deploy project **`mutande-mcp`** (or rename `deploy` task).
2. Custom domain: `mcp.mutande.online`.
3. Env: copy from `.env.example` (`AUTH0_DOMAIN`, `AUTH0_AUDIENCE`, `MUTANDE_HUB_URL`, `MCP_PUBLIC_URL`).
4. Hub: set `MCP_ENDPOINT=https://mcp.mutande.online` if not using the built-in default.
5. `cd mcp && deno task deploy`

## Auth0 app / tenant config needed

Documented in [`docs/AUTH0.md`](../docs/AUTH0.md) §8. Summary:

1. **Reuse** API audience `https://hub.mutande.app` (L0 default) so MCP→hub calls work with one token.
2. Tenant **Advanced**: enable **Resource Parameter Compatibility Profile** and **Include Issuer in Authorization Responses** (MCP client discovery).
3. Promote DB / social connections to **domain-level** so third-party MCP clients (ChatGPT, Claude) can use them.
4. Enable **Dynamic Client Registration** *or* manually register ChatGPT / Claude redirect URIs (see Auth0 “Register your MCP Client Application”).
5. Optional later: separate Auth0 API identifier `https://mcp.mutande.online` + OBO to hub (`AUTH0_MCP_AUDIENCE`).

## ChatGPT / Claude.ai connector setup

1. Finish mutande onboarding (Mac or web) with the same Auth0 account you will use in the host.
2. In ChatGPT (or Claude.ai) → **Settings → Connectors / MCP** → add remote MCP server URL:
   ```
   https://mcp.mutande.online/mcp
   ```
3. Complete the OAuth browser login (Auth0 Universal Login on `auth.mutande.online`).
4. After connect, call tool **`health`** — should show your handle and a web `agent_id`.
5. Inbox tools remain stubbed until L2; use the Mac sidecar for real E2E mail today.

Local Inspector:

```bash
npx @modelcontextprotocol/inspector
# Transport: Streamable HTTP
# URL: http://127.0.0.1:3849/mcp
# Auth: paste an Auth0 access token with audience https://hub.mutande.app
```

## Still stubbed / deferred

- Full Streamable HTTP SSE (GET `/mcp`) and hub SSE wake
- OBO token exchange when MCP audience ≠ hub audience
- Inbox tools (`list_threads`, …) — L2
- Capability handshake UI / transport chips — L1
- `app_envelope` delivery, external contacts, billing — L3/L4

Local `core` stdio MCP path is **not** modified by this package.
