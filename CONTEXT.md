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
| Color | Stone base + amber for pending; emerald for confirmed; ink for actions. Map below — do not invent a fourth ramp |
| Density | Compact tray app; status at a glance (`open` · `2/3 replied` · needs you) |
| Motion | Minimal — badge updates only |
| Trust UX | Safety-number verify like Signal/1Password — serious, not playful |

**Avoid:** Web3 gradients, chat bubbles, dev-tool dark defaults, mythic kitsch (columns, lightning, togas).

### Color map

Record of colors in use. Not a retint. Host marks (Cursor, Claude, ChatGPT) stay their own product colors.

**Mac app** — `app/lib/theme/mutande_macos_theme.dart` (`MutandeColors`). Tailwind stone. This is what Threads and Collab paint today.

| Token | Hex | Role |
|-------|-----|------|
| stone50 | `#FAFAF9` | Cards, sheets |
| stone100 | `#F5F5F4` | Canvas |
| stone200 | `#E7E5E4` | Lines, empty heat |
| stone400 | `#A8A29E` | Hints, timestamps |
| stone500 | `#78716C` | Secondary text |
| stone600 | `#57534E` | Filled buttons, open chips |
| stone800 | `#292524` | Titles, primary buttons, done |
| bronze | `#92400E` | Doing, focus ring, donut “doing”, heat peak |
| bronzeSoft | `#F5EDE6` | Doing chip plate |
| amber | `#B45309` | Needs you, pending |
| amberSoft | `#FEF3C7` | Needs-you chip, mid heat |
| emerald | `#166534` | Linked, verified |
| emeraldSoft | `#ECFDF5` | Confirmed plate |

App bar ink is stone700 `#44403C` (not a named token). Splash and barriers use stone950 `#0C0A09`.

**Site** — `web/src/app/globals.css`. Warmer OKLCH stone, separate from the Mac hexes. Approx sRGB:

| Token | Approx hex | Role |
|-------|------------|------|
| stone-50 | `#FBFAF7` | Page background |
| stone-100 | `#F4F2EC` | Surface mix |
| stone-200 | `#E5E1D9` | Soft wash |
| stone-300 | `#CAC3B9` | Borders (70% mix) |
| stone-500 | `#797065` | Muted |
| stone-700 | `#494138` | — |
| stone-800 | `#2F2721` | — |
| stone-900 | `#201914` | Strong buttons (also Tailwind `stone-900` utilities) |
| slate-ink | `#271D16` | Body text |
| accent | `#883C00` | Brand bronze |
| accent-soft | `#F9E8D6` | Tint |
| amber | `#D09945` | Gold signal |

Landing pages also use Tailwind `stone-*`, `amber-*`, and `red-*` utilities, which are the Mac ramp, not these OKLCH tokens.

**Video** — `video/src/theme.ts` and `video-mc/src/theme.ts`. Hand hexes, closer to the site than to the Mac app.

| Token | Hex |
|-------|-----|
| stone50–300 | `#FAF9F7` `#F5F3EF` `#E8E4DC` `#D4CDC2` |
| stone400 | `#A8A29E` (same as Mac) |
| stone500 / 700 | `#8A8478` `#5C564C` |
| stone800 / 900 | `#292524` `#1C1917` (same as Mac / Tailwind) |
| accent | `#8B5A2B` |
| amber | `#D4A24C` |

Demo addresses in the video only: alice `#6B8F71`, bob `#7A6B8F`, mary `#B07A4A`, cfo `#5A7A8A`.

**Drift** — same roles, different hexes, not part of `MutandeColors`:

- Settings bronze `#8B6914` and plate `#F5F0E6` (file-local `_kBronze`)
- Compose capsule grays `#E9E6E0` `#D2CDC5` `#BDB6AD` `#8E877E` `#B7B1A8`
- Person plates `#E8E4DC` `#D6CFC6` (video stone, not Mac stone)
- Heat step `#E8D5C4`
- Danger is three reds: `#991B1B`, `#9F1239`, `#B91C1C`, with plates `#FEF2F2` `#FEE2E2` `#FECACA`
- One bright success `#16A34A` / `#DCFCE7` beside emerald
- Stone300 `#D6D3D1`, stone700 `#44403C`, stone900 `#1C1917` are used raw in Settings and Agents and are not on `MutandeColors`
