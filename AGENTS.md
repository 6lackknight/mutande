# Mutande

Agent-to-agent encrypted mail for teams. Domain terms: **thread**, **bundle**, **handoff**, **org**, **handle** (`alice@acme`), **broadcast** (`@all@acme`).

## Monorepo

- `app/` — Flutter macOS menu-bar / tray UI
- `core/` — Rust daemon + MCP (`mutande-core`)
- `hub/` — Deno Deploy API (Deno KV for inline envelopes)
- `proto/` — JSON schemas
- `skill/` — agent skill for supported hosts

## v1

macOS only. Supported AI hosts: Cursor, Claude Desktop, ChatGPT desktop. E2E via local core; hub is blind courier.

Human decisions: AskQuestion on Cursor when available; structured chat fallback elsewhere. No hub-side guardrails.

Large payloads: R2 blobs (envelope carries blob ref); free tier sized to R2 free; premium for large codebase/video-style shares.

## v1.5

iOS Mutande app: full E2E companion (read, reply, blobs, push). Multi-device pubkeys per handle. Agents stay on desktop; mobile ChatGPT is unrelated.

## Learned User Preferences

- Prefer AskQuestion UI for product decisions and design interviews when available.
- Keep setup everyday-user friendly; connect AI hosts one at a time via picker with large consistent host icons; hide hub URL and debug controls from Join/onboarding UI.
- Prioritize end-to-end PRD flow over UI polish until the core path works.
- Daemon/transport failures are not onboarding: keep last-known configured state; Keychain-aware copy with bootstrap retries; offer Retry and Restart courier; sidecar must not kill core during Keychain unlock (60s wait); never reset to Join.
- On "stop", halt all agents and work immediately; pause and confirm intent before continuing.
- Show the product name as lowercase `mutande` in all user-facing copy; brand mark is an MT ligature (m/t share a stem), white on solid black for tray/icon assets.
- Auth is greenfield Auth0-only — do not restore hub JWT or `POST /v1/auth/register`.
- On Mac launch, show a short dark welcome splash with the thinking orb before the main UI.
- Ship hardcoded Auth0/hub production defaults for Mac/daemon when env is unset; env still overrides; domain churn later is OK.
- Prefer Developer ID + notarized DMG for Mac v1 distribution; defer Mac App Store until the product can live in sandbox (daemon sidecar + silent MCP config writes conflict today).
- Mac app chrome stays minimal: primary tabs for threads and routing (contacts optional third); routing graph shows default-agent hierarchy with Add-on-empty-node for sub-agents; default window 1280×720 (min 960×540); Settings as bottom sheet (opens bottom-up, X to close); tuck the rest under Settings.
- Thread UI: nested replies yes; skip Reddit-style up/downvotes and deep social threading — agent mail, not forum.

## Learned Workspace Facts

- Visual lane is mythic subtle: macOS-native quiet courier with a light messenger motif; details in `CONTEXT.md`.
- Crypto seam is wrap-to-N (seal once, N device wraps); glossary lives in `CONTEXT.md`.
- Flutter app talks to core over local HTTP RPC at `http://127.0.0.1:3847` (`Authorization: Bearer` / `X-Mutande-Token` from `~/.mutande/daemon_http_token`); MCP uses Unix socket at `~/.mutande/daemon.sock`.
- Hub at Deno Deploy `https://mutande.6lackknight.deno.net`; prod web `https://mutande.vercel.app` until `mutande.ai`; Auth0 JWKS on hub; audience `https://hub.mutande.app`; `web/` is Next.js + Auth0 on Vercel for signup/invites; desktop/mobile share the same Auth0 account.
- Mac Auth0 login is Native + loopback callback (`http://127.0.0.1:<port>/callback`); defaults live in `core/src/daemon/auth0_defaults.rs`.
- Onboarding is self-serve create-team or join-invite; org slug is user-picked; handle defaults to `email-local@org`.
- Large payloads use private R2 with object key prefix `blobs/{id}` (`R2_*` hub env).
- Flutter thinking UI uses a single **working** orb (tilted particle orbits) for all loading states.
- Agent addresses use `handle/agent` (`alice@acme/claude`); bare handle is the default agent; never show `/default` as a user-facing address; for self-collaboration allow short `@agent` (e.g. `@claude`); personal `@all` means all of the user's own agents (distinct from org broadcast `@all@acme`).
- Mac app bundle id is `ai.mutande.app`; bundles `mutande-core` sidecar in app Resources and launches it on startup; v1 ships as notarized DMG via `scripts/release-macos-dmg.sh`, with download on prod web.
- Public docs at `/docs` via Nextra in `web/`, same Vercel deploy as marketing/auth (not a separate deploy).
- Thread messages nest via bundle `in_reply_to` and hub `parent_message_id`. Agent upvotes (up-only, one per agent_id, toggle) signal coordination weight on a message; MCP tool `upvote_message`.
