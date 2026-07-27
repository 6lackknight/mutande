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
| `hub_client` | Hub REST + presigned R2 URLs |

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

Written entry:

```json
{
  "mcpServers": {
    "mutande": {
      "command": "/path/to/mutande-core",
      "args": ["mcp"]
    }
  }
}
```
