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

Ordered by severity. Do not ship a notarized DMG until High items are addressed or explicitly accepted.

### High

- [ ] **Stop tracking sidecar binary in git** — remove `app/macos/Runner/Resources/mutande-core` from the repo, gitignore it, rely on `bundle_mutande_core.sh` / `scripts/release-macos-dmg.sh` to copy from `core/target/release/`
- [ ] **Tighten Release Hardened Runtime entitlements** — re-evaluate `com.apple.security.cs.disable-library-validation` and `allow-unsigned-executable-memory` on Release; avoid stamping app entitlements onto every nested framework in `release-macos-dmg.sh` unless required

### Medium

- [ ] **Welcome splash keeps `RootScreen` mounted** — overlay splash on `child` (Stack) so tray Connect / status listeners work during the 3s hold (`app/lib/widgets/welcome_splash.dart`)
- [ ] **Splash version from pubspec** — pass real app version into `WelcomeSplash` (not hardcoded `1.0.0`)
- [ ] **Connect success `ExpansionTile` controlled state** — reset/collapse Details when `connectResult` changes (`app/lib/screens/session_screen.dart`)
- [ ] **Align primary IA with AGENTS preference** — threads (+ optional contacts) as primary; tuck Agents / Session chrome under Settings
- [ ] **Auth0 resolver unit test env-isolation** — `auth0_resolvers_fall_back_to_builtin_defaults` must not fail when `AUTH0_*` is set in the environment (`core/src/daemon/state.rs`)

### Low

- [ ] **UTF-8-safe `_rpcOk` in widget tests** — encode JSON as UTF-8 bytes so future unicode notes don’t break `http.Response`
- [ ] **`ConnectHostResult` equality** (optional) — value `==` if result instances are ever reused across rebuilds

## Remaining deferred

- Sparkle + notarization credential profile (see `docs/UPDATES.md`)
- Flutter Unix-socket transport (still HTTP bridge + token)
- ChatGPT MCP config path confirmation across desktop builds
- Own safety-number URI uses handle `me` until hub `/me` is wired into that RPC
- Verify UI shows QR *payload* stub (copyable URI), not a rendered QR bitmap

## Last code review

**2026-07-28** — Highs: tracked `mutande-core` binary; loose Release library-validation entitlements. Mediums: splash unmounts child + hardcoded version; ExpansionTile desync; IA vs AGENTS; env-fragile Auth0 test. Flutter widget tests green after ASCII mock note fix. See **Fix todo** above.
