# Mutande v1 plumbing — status

Branch: `main`

## Shipped this session

| Priority | Status |
|----------|--------|
| 1. Bundle `mutande-core` sidecar; app start/stop; `MUTANDE_CORE_PATH` | Done — `CoreSidecar`, Xcode bundle script, daemon `set_core_path` / `persist_own_exe_path` |
| 2. Flutter thread UI list/open/reply | Done — Threads / Agents / Contacts + Settings over daemon RPCs |
| 3. Safety-number / verify contact | Done — fingerprint + QR payload stub + compare RPC |
| 4. Blob send path E2E | Done — `forward_blob` / auto-blob draft + wiremock E2E open |
| 5. Sparkle / updates | Documented stub in `docs/UPDATES.md` (explicit gap) |
| 6. Auth0 native login + agent addresses (`handle/agent`) | Done — loopback PKCE, hub/core address layer, defaults |

## Already done (prior)

Crypto seal/open, hub API, hub_client, daemon+MCP, Keychain, get_thread decrypt,
connect_host, onboarding/register, menu bar tray, R2-shaped presign, blob
`seal_to_temp`, review hardening (HTTP bearer, register atomic, R2 deploy guard,
refresh token, socket/dir perms, open_error without ciphertext). App Sandbox off
for Mac accessory; Release has `network.client` + `network.server`.

## Out of scope

v1.5 iOS companion.

## Fix todo (code review 2026-07-28)

### High

- [x] **Stop tracking sidecar binary in git** — removed from index; gitignored; build scripts still copy from `core/target/release/`
- [x] **Tighten Release Hardened Runtime entitlements** — dropped `disable-library-validation` + `allow-unsigned-executable-memory` from Release; frameworks signed runtime-only; sidecar uses `Sidecar.entitlements`
- [x] **Outbound agent visibility leak** — `thread_visible_for_agent` only ORs audience match for same-user self-handoff; regression test added

### Medium

- [x] **Welcome splash keeps `RootScreen` mounted** — overlay on Stack over `child`
- [x] **Splash version from pubspec** — `APP_VERSION` dart-define (`AppConfig.appVersion`); release script passes it
- [x] **Connect success `ExpansionTile` controlled state** — epoch `ValueKey` resets Details on new result
- [ ] **Align primary IA with AGENTS preference** — threads (+ optional contacts) as primary; tuck Agents / Session chrome under Settings
- [x] **Auth0 resolver unit test env-isolation** — fallback asserts skip when `AUTH0_*` env is set

### Low

- [x] **UTF-8-safe `_rpcOk` in widget tests** — `Response.bytes(utf8.encode(...))`
- [x] **`ConnectHostResult` equality** — value `==` / `hashCode` on result + host rows

## Remaining deferred

- Sparkle + notarization credential profile (see `docs/UPDATES.md`)
- Flutter Unix-socket transport (still HTTP bridge + token)
- ChatGPT MCP config path confirmation across desktop builds
- Own safety-number URI uses handle `me` until hub `/me` is wired into that RPC
- Verify UI shows QR *payload* stub (copyable URI), not a rendered QR bitmap
- Primary IA refactor (Agents tab → Settings) — see open Medium above
- Self-handoff inbox overwrite (sender→recipient/pending) is intentional for `needs_action`

## Last code review

**2026-07-28 (fix pass)** — Closed Highs/Mediums above except IA alignment. If notarized Flutter build fails without library-validation, re-evaluate Release entitlements narrowly.
