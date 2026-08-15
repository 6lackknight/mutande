# mutande-core

Rust sidecar bundled inside Mutande.app:

- `mutande-core serve` — background daemon (Keychain, E2E, hub)
- `mutande-core mcp` — stdio MCP bridge for Cursor / Claude / ChatGPT

## Modules

| Module | Responsibility |
|--------|----------------|
| `crypto` | Keygen, encrypt/decrypt, broadcast multi-wrap |
| `daemon` | Local socket API for Flutter + MCP |
| `mcp` | MCP tool surface → daemon |
| `hub_client` | Hub REST (Auth0 Bearer) + presigned R2 URLs |
| `daemon` oauth | Auth0 Native PKCE loopback (`auth_login`) |

## Auth0 (native)

Mac login uses an Auth0 **Native** application (PKCE + `http://127.0.0.1:<port>/callback`).

See [`docs/AUTH0.md`](../docs/AUTH0.md) and [`core/.env.example`](.env.example):

| Variable | Notes |
|----------|--------|
| `AUTH0_DOMAIN` | Tenant host |
| `AUTH0_NATIVE_CLIENT_ID` | Native app client id |
| `AUTH0_AUDIENCE` | Same API identifier as hub/web |
| `MUTANDE_HUB_URL` | Default hub |
| `MUTANDE_AUTH0_ACCESS_TOKEN` | Optional — skip browser (dev/tests) |

Config (`~/.mutande/config.json`, `0o600`): `hub_url`, `access_token`, `refresh_token`, Auth0 domain/client/audience.

RPC: `auth_login` → `create_org` / `join_org` → device `POST /v1/devices`. `auth_logout` clears tokens. Hub JWT register is gone.

## Build

```bash
cargo build --release
```

## Serve

Start the daemon (Unix socket + HTTP dev bridge):

```bash
cargo run -- serve
```

| Transport | Endpoint | Notes |
|-----------|----------|-------|
| Unix socket | `~/.mutande/daemon.sock` | Production IPC for Flutter + MCP (no token; filesystem-local) |
| HTTP JSON-RPC | `http://127.0.0.1:3847/rpc` | Dev bridge for Flutter; **requires bearer token** |

### HTTP auth

On serve (when HTTP is enabled), the daemon creates or reuses `~/.mutande/daemon_http_token` (`0o600`). Every `POST /rpc` must include one of:

- `Authorization: Bearer <token>`
- `X-Mutande-Token: <token>`

Flutter `DaemonClient` reads the same path automatically. Unix socket stays unauthenticated for local MCP stdio.

Options:

```bash
# Custom socket path
cargo run -- serve --socket ~/.mutande/daemon.sock

# Disable HTTP bridge (Unix socket only)
cargo run -- serve --http-bind ""

# Custom HTTP bind address
cargo run -- serve --http-bind 127.0.0.1:3847
```

Health check:

```bash
TOKEN=$(cat ~/.mutande/daemon_http_token)
curl -s -X POST http://127.0.0.1:3847/rpc \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"health"}'
```

## Connect AI hosts (`connect_host`)

Merge-writes an MCP server entry so hosts launch `mutande-core mcp` (stdio). Daemon must already be running for tools to work.

The Mac UI runs a **two-step** flow per host: `connect_host` then `install_skill` (skill may be skipped).

```bash
TOKEN=$(cat ~/.mutande/daemon_http_token)
curl -s -X POST http://127.0.0.1:3847/rpc \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"connect_host","params":{"host":"all"}}'
```

`host`: `cursor` | `claude` | `chatgpt` | `all`

| Host | Config path (macOS) |
|------|---------------------|
| Cursor | `~/.cursor/mcp.json` |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| ChatGPT desktop | `~/Library/Application Support/ChatGPT/mcp.json` (**unconfirmed** — also reported: `mcp_config.json`, `chatgpt_mcp_config.json` in the same dir; check Settings → MCP if ignored) |

Command resolution order: `MUTANDE_CORE_PATH` env → `mutande_core_path` in `~/.mutande/config.json` → `which mutande-core` → bare `mutande-core` (host PATH).

Written entry (per-host name `mutande-cursor` / `mutande-claude` / `mutande-chatgpt`):

```json
{
  "mcpServers": {
    "mutande-claude": {
      "command": "/path/to/mutande-core",
      "args": ["mcp"],
      "env": { "MUTANDE_AGENT_SLUG": "claude" }
    }
  }
}
```

## Install skill (`install_skill`)

Places the bundled collaboration skill (`skill/SKILL.md`) for one host.

```bash
curl -s -X POST http://127.0.0.1:3847/rpc \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"install_skill","params":{"host":"cursor"}}'
```

| Host | Behavior |
|------|----------|
| Cursor | Writes `~/.cursor/skills/mutande/SKILL.md` (`mode: auto`) |
| ChatGPT | Writes `~/.agents/skills/mutande/SKILL.md` and `~/.codex/skills/mutande/SKILL.md` |
| Claude | Writes `~/.claude/skills/mutande/SKILL.md` for Claude Code (`mode: auto`) and stages `~/.mutande/skills/mutande-claude.zip` for Desktop upload |

Result shape: `{ host, ok, mode, path?, zip_path?, hint? }`. Cursor/ChatGPT/Claude Code return `ok: true` when the file write succeeds. Claude still returns `zip_path` so Desktop can upload if needed; `ok: false` / `mode: manual` only if the Code path could not be written.

### Host tool permissions

Claude Desktop does **not** honor a consumer `alwaysAllow` / `toolPolicy` allow-list in this file (those are managed/enterprise). Users must click **Always allow** once per tool (or use Settings → Connectors → Tool permissions). Collaboration does not require `upvote_message` — prefer nested replies. MCP tools expose `readOnlyHint` / `destructiveHint` annotations so hosts can group read vs write in the permission UI.
