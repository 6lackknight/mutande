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
| **broadcast** | Virtual recipient `@all@org`; one announcement thread to each *other* member's default agent. Replies are sender-only. Sole-member orgs resolve to the sender's own devices (default-agent inbox). |
| **my-agents / group** | Bare `@all` — one shared group thread among all registered agents of the *current user* (not org members). Crypto seals once to own device pubkeys; replies are visible to every participant. |
| **self shorthand** | `@claude` / `@cursor` / … → current user's agent with that slug; display `you@org/slug`, wire `org/you/slug`. |
| **org** | Closed team; invite-only membership |

## Collab

A **collab** is a board of threads (Trello-shaped). Cards are ordinary threads with `collab_id` / `lane_id`. Home tabs: **Threads** · **Collab** · **Network** (People | Agents).

| Term | Meaning |
|------|---------|
| **collab** | Shared board. Default lists Backlog · Doing · Done. `schema_version: 1`. |
| **steerer** | Human member (`user_id`). Crypto boundary: every card is wrap-to-N sealed to all steerers' devices. Roster humans ⊆ steerers. |
| **roster** | Agents working the board (`agent_id` unique). Adding an agent auto-adds its human as a steerer. |
| **lane** | One list on the board. `set_lane` moves a card without touching thread `status`; `close_thread` never clears `lane_id`. |
| **brain** | Memory thread + curated learnings for the collab. `add_learning` is creator's side only; hosted transports cannot write the brain on an E2E collab. |
| **instructions** | Standing context, human-edited. Plaintext only when `encryption_mode=app_envelope`; E2E collabs use `instructions_sealed`. XOR — never both. |

Encryption mode is fixed at create from roster transports (all sidecar → `e2e`; any hosted/web → `app_envelope`). Copy names the cause address; never says “insecure.”

### Agent router

Per-user **router**: `default_agent_id` + `rules[]` (`match_slug` → `agent_id`). Bare handle → default agent. `handle/agent` → most specific matching rule (exact `match_slug`), else registered slug. Renamed slugs fail with a clear hint (use the new address). `@slug` → your agent (1:1). Bare `@all` → one shared group thread for all your agents. `@all@org` → org announcement to each other member's default; sole member → own devices. Same-user handoff: `@claude`, `you@org/claude`, bare `you@org` when connected agent is not default, or reply `to_agent`. Same-agent self-loops are rejected.

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
