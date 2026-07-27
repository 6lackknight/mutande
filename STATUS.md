# Mutande v1 plumbing — status

Branch: `cursor/mutande-macos-v1-plumbing-ec11`

## Shipped this session

| Priority | Status |
|----------|--------|
| 1. Bundle `mutande-core` sidecar; app start/stop; `MUTANDE_CORE_PATH` | Done — `CoreSidecar`, Xcode bundle script, daemon `set_core_path` / `persist_own_exe_path` |
| 2. Flutter thread UI list/open/reply | Done — Threads / Verify / Session tabs over daemon RPCs |
| 3. Safety-number / verify contact | Done — fingerprint + QR payload stub + compare RPC |
| 4. Blob send path E2E | Done — `forward_blob` / auto-blob draft + wiremock E2E open |
| 5. Sparkle / updates | Documented stub in `docs/UPDATES.md` (explicit gap) |

## Already done (prior)

Crypto seal/open, hub API, hub_client, daemon+MCP, Keychain, get_thread decrypt,
connect_host, onboarding/register, menu bar tray, R2-shaped presign, blob
`seal_to_temp`, review hardening (HTTP bearer, register atomic, R2 deploy guard,
refresh token, socket/dir perms, open_error without ciphertext).

## Out of scope

v1.5 iOS companion.

## Remaining Medium/Low / deferred

- Sparkle + notarization (see `docs/UPDATES.md`)
- Flutter Unix-socket transport (still HTTP bridge + token)
- ChatGPT MCP config path confirmation across desktop builds
- Widget tests beyond smoke; full host MCP QA on real macOS
- Own safety-number URI uses handle `me` until hub `/me` is wired into that RPC
- Verify UI shows QR *payload* stub (copyable URI), not a rendered QR bitmap

## Last code review

**Verdict: no Critical/High remaining** (post-fix: blob opaque-decode gated on
`blob_id`; sidecar persists core path even when daemon already up; stdout/stderr
drained to avoid pipe deadlock).
