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
- Keep setup everyday-user friendly; avoid developer-only onboarding paths; hide hub URL and debug controls from Join/onboarding UI.
- Prioritize end-to-end PRD flow over UI polish until the core path works.
- Daemon/transport failures are not onboarding: keep last-known configured state and show retry, never reset to Join.
- On "stop", halt all agents and work immediately; pause and confirm intent before continuing.
- Show the product name as lowercase `mutande` in all user-facing copy.
- Auth is greenfield Auth0-only — do not restore hub JWT or `POST /v1/auth/register`.
- Brand mark is an MT ligature (m/t share a stem); prefer white mark on solid black for tray/icon assets.
- On Mac launch, show a short dark welcome splash with the thinking orb before the main UI.
- Ship hardcoded Auth0/hub production defaults for Mac/daemon when env is unset; env still overrides; domain churn later is OK.

## Learned Workspace Facts

- Visual lane is mythic subtle: macOS-native quiet courier with a light messenger motif; details in `CONTEXT.md`.
- Crypto seam is wrap-to-N (seal once, N device wraps); glossary lives in `CONTEXT.md`.
- Flutter app talks to core over local HTTP RPC at `http://127.0.0.1:3847` (`Authorization: Bearer` / `X-Mutande-Token` from `~/.mutande/daemon_http_token`); Unix socket is the daemon-native MCP path.
- Hub deploys to Deno Deploy at `https://mutande.6lackknight.deno.net`.
- Prod web is `https://mutande.vercel.app` until `mutande.ai`; Auth0 JWKS validates access tokens on the hub; canonical Auth0 API audience is `https://hub.mutande.app`; `web/` is Next.js + Auth0 on Vercel for signup/invites; desktop/mobile share the same Auth0 account.
- Mac Auth0 login is Native + loopback callback (`http://127.0.0.1:<port>/callback`); defaults live in `core/src/daemon/auth0_defaults.rs`.
- Onboarding is self-serve create-team or join-invite; org slug is user-picked; handle defaults to `email-local@org`.
- Large payloads use private R2 with object key prefix `blobs/{id}` (`R2_*` hub env).
- Flutter thinking UI uses orb modes: searching (idle/standard) and working (active loading).
