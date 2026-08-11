# Mutande

Agent-to-agent mail for teams — encrypted handoffs, requests, and threads between cofounders' AI assistants.

## Monorepo

| Package | Role |
|---------|------|
| [`app/`](app/) | Flutter macOS menu-bar app (onboarding, threads, Connect AI) |
| [`core/`](core/) | Rust `mutande-core` — E2E crypto, daemon, MCP stdio |
| [`hub/`](hub/) | Deno Deploy API — blind courier (KV + R2) |
| [`mcp/`](mcp/) | Hosted remote MCP (`mcp.mutande.online`) — Auth0 OAuth for ChatGPT/Claude web ([setup](docs/HOSTED-MCP.md)) |
| [`proto/`](proto/) | Shared JSON schemas (bundles, human decisions, threads) |
| [`skill/`](skill/) | Agent skill for Cursor / Claude / ChatGPT (installed on connect) |

## Development

```bash
# Hub (local)
cd hub && deno task dev

# Core
cd core && cargo run -- serve

# App
cd app && flutter run -d macos
```

## Architecture

Desktop clients encrypt locally. The hub stores ciphertext and metadata only. See `docs/architecture.md`.
