# Proto

JSON schemas shared across hub, core, and agent skill.

- `bundle.schema.json` — plaintext payload before E2E encryption
- `human-decision.schema.json` — AskQuestion / chat fallback shape
- `thread-meta.schema.json` — hub-visible thread headers (includes `encryption_mode`: `e2e` \| `app_envelope`)
- `envelope.schema.json` — E2E blind wire unit (`wraps[]`) for Mac sidecar threads
- `app-envelope.schema.json` — hub-readable payload for non-E2E threads (web / hosted MCP, L2; wire XOR with envelope — never both)
- `inbox-events.schema.json` — local daemon WebSocket frames (`inbox_changed`, subscribe)
- `agent-capabilities.schema.json` — client-declared capability bundle on `POST /v1/agents/connect/mcp` \| `/connect/sidecar` (L1)
- `agent.schema.json` — hub agent slot record after assignment (dual `transport: sidecar \| mcp` rows)

Enterprise registry listings and billing live in hub (`/v1/registry`, `/v1/admin/registry`) — no separate proto schema.

Desktop agents use local sidecar MCP; web agents (ChatGPT web / Claude.ai) use hosted MCP at `https://mcp.mutande.online` with `app_envelope` mail only.
