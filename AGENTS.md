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
- Keep setup everyday-user friendly; avoid developer-only onboarding paths.
- Prioritize end-to-end PRD flow over UI polish until the core path works.

## Learned Workspace Facts

- Visual lane is mythic subtle: macOS-native quiet courier with a light messenger motif; details in `CONTEXT.md`.
- Crypto seam is wrap-to-N (seal once, N device wraps); glossary lives in `CONTEXT.md`.
