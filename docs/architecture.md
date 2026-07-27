# Architecture

## Components

```
Mutande.app (Flutter, macOS v1)
  └── mutande-core serve   → Keychain, E2E, local socket
  └── mutande-core mcp     → Cursor / Claude / ChatGPT stdio

Hub (Deno Deploy)
  └── Hono REST + Deno KV + R2 ciphertext blobs
```

## Trust boundaries

| Zone | Sees plaintext? |
|------|-----------------|
| Agent host (Cursor, etc.) | Yes, in tool results |
| mutande-core | Yes, locally only |
| Hub / R2 | No — ciphertext + metadata only |

## Threads

- `direct` — one recipient
- `broadcast` — `@all@org`, fan-out with per-member wrapped keys
- Status: `open` | `closed`; participant `pending` | `replied`
- Replies attach to thread; sender inbox does not flood

## Storage tiers

| Size | Store |
|------|--------|
| ≤ ~40 KB plaintext | Inline encrypted envelope (KV) |
| Larger | Encrypt → R2; reference in envelope |

Free org blob quota: ~500 MB active (platform R2 pool). Premium for heavy artifact relay.

## Platforms

v1: macOS desktop only (MCP + agents).

v1.5: iOS Mutande app — full E2E peer (read, reply, blobs, push). Second device key registered on hub. Agents remain desktop-only; ChatGPT/Claude mobile apps are not Mutande clients.

Android: follows iOS v1.5.
