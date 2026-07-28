# Mutande domain glossary

Terms for threads, handoffs, and the crypto seam. Use these names in code and docs.

## Mail

| Term | Meaning |
|------|---------|
| **thread** | Conversation container with `open` / `closed` status; holds handoffs and replies |
| **bundle** | Plaintext payload before E2E encryption (questions, resources, answers) |
| **handoff** | Outbound bundle from sender to recipient(s) |
| **handle** | Human address, e.g. `alice@acme` (bare → recipient default agent) |
| **agent handle** | Display routing suffix, e.g. `alice@acme/claude`; wire path `acme/alice/claude` |
| **agent_id** | Stable UUID per agent slot; threads reference this, slug is renameable |
| **broadcast** | Virtual recipient `@all@org`; fans out to each member's default agent only |
| **org** | Closed team; invite-only membership |

### Agent router

Per-user **router**: `default_agent_id` + `rules[]` (`match_slug` → `agent_id`). Bare handle → default agent. `handle/agent` → most specific matching rule (exact `match_slug`), else registered slug. Renamed slugs fail with a clear hint (use the new address). `@all@org` → each member's default only. Self-handoff via reply `to_agent`.

## Crypto seam (wrap-to-N)

| Term | Meaning |
|------|---------|
| **device** | One registered client (Mac, iPhone) with its own keypair |
| **DevicePubKey** | X25519 public key for a device; crypto input — not handles |
| **RecipientSet** | Flat list of device pubkeys after handle/@all resolution (done outside crypto) |
| **envelope** | Hub-visible wire unit: one content ciphertext + `wraps[]` (one boxed content-key per recipient device) |
| **wrap** | Content encryption key encrypted to one device pubkey |
| **seal** | Encrypt bundle bytes once; produce envelope with N wraps |
| **open** | Decrypt envelope with local device secret key |
| **IdentityStore** | Adapter seam for Keychain / memory (beside daemon, not on seal hot path) |

## Storage tiers

| Term | Meaning |
|------|---------|
| **inline envelope** | Small handoff in Deno KV (~40 KB plaintext comfort zone) |
| **blob** | Large encrypted artifact in R2; envelope carries `blob_id` + wrapped blob key |

## Visual language (v1)

**Lane:** mythic subtle — macOS-native quiet courier with a faint messenger motif.

| Pillar | Direction |
|--------|-----------|
| Platform | Menu bar, SF Pro, system light/dark, vibrancy |
| Mood | Calm, trustworthy; cofounder infrastructure — not chat, not crypto-bro |
| Motif | Relay / handoff — envelope icon, threads as relays; no literal Greek UI |
| Color | Stone/slate base + one accent; emerald open, amber pending, muted closed |
| Density | Compact tray app; status at a glance (`open` · `2/3 replied` · needs you) |
| Motion | Minimal — badge updates only |
| Trust UX | Safety-number verify like Signal/1Password — serious, not playful |

**Avoid:** Web3 gradients, chat bubbles, dev-tool dark defaults, mythic kitsch (columns, lightning, togas).
