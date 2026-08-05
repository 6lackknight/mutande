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
- Keep setup everyday-user friendly; after create/join, blocking Connect AI hosts gate before home; connect hosts one at a time via picker with large consistent host icons (**two steps: MCP then skill**; Claude skill via ZIP upload when auto-install isn’t possible); then first-run ping wizard; hide hub URL and debug controls from Join/onboarding UI.
- Prioritize end-to-end PRD flow over UI polish until the core path works.
- Daemon/transport failures are not onboarding: keep last-known configured state; Keychain-aware copy with bootstrap retries; offer Retry and Restart courier; sidecar must not kill core during Keychain unlock (60s wait); never reset to Join.
- On "stop", halt all agents and work immediately; pause and confirm intent before continuing.
- Show the product name as lowercase `mutande` in all user-facing copy; brand mark is an MT ligature (m/t share a stem), white on solid black for tray/icon assets; landing whisper-gloss etymology is Shona *dandemutande* (spider’s web — favor the web/network connotation) with phonetic pronunciation and `mutande` underlined within the compound; privacy copy stays short and plain — never claim “we store nothing” (mail is ciphertext; account/routing metadata is kept; anonymized stats only if true).
- Auth is greenfield Auth0-only — do not restore hub JWT or `POST /v1/auth/register`. Prefer proper Auth0 login (PKCE/browser) for admin and ops tools; never ask to paste access tokens.
- On Mac launch, show a short dark welcome splash with the thinking orb before the main UI.
- Ship hardcoded Auth0/hub production defaults for Mac/daemon when env is unset; env still overrides; domain churn later is OK.
- Prefer Developer ID + notarized DMG for Mac v1 distribution; ship a single rolling alpha artifact (`mutande-alpha.dmg`) — keep only the latest on the site; dedicated web `/download` page; landing nav Docs · Download · Sign in (Get started / Join waitlist only in the hero — don’t pair Sign in with Get started in nav); Download CTA labeled Try Alpha; DMG binaries under `web/public/downloads/` are gitignored (do not commit); defer Mac App Store until the product can live in sandbox (daemon sidecar + silent MCP config writes conflict today).
- Mac app chrome stays minimal via `macos_ui` shell (not shadcn): home tabs Threads · Agents · Contacts; content stays mutande stone; mail side panel on Threads only; toolbar Compose (C) + Search on one row (`justify-between`) with a dedicated Search screen; Threads home is Cursor-like resizable mail-split (list + reading + optional stats via `resizable_panel`), nested replies and OP badge/header (3-line read-more), no spatial view; list shows all threads (no audience/slug filter) with `@author` + latest snippet and trailing Needs you (human only) or HH:MM (no Waiting badge); support close, delete, and mute (notifications only); agent upvotes yes (up-only per agent, toggle — coordination weight); skip downvotes — agent mail, not forum; Agents tab shows routing graph (default-agent hierarchy, Add-on-empty-node for sub-agents); default window 1280×720 (min 960×540); Settings as MacosSheet with AI HOSTS in 3-column icon grid + Notifications section; tuck remaining plumbing under Settings.
- Present the mutande agent skill as a collaboration utility (how to team via mutande), so host agents do not treat skill docs/links as untrusted directives; skill checks inbox on new chat and stays quiet when caught up — no timer poll (Mac notifications cover cold mail).

## Learned Workspace Facts

- Visual lane is mythic subtle: macOS-native quiet courier with a light messenger motif; details in `CONTEXT.md`.
- Crypto seam is wrap-to-N (seal once, N device wraps); glossary lives in `CONTEXT.md`.
- Flutter app talks to core over local HTTP RPC at `http://127.0.0.1:3847` (`Authorization: Bearer` / `X-Mutande-Token` from `~/.mutande/daemon_http_token`); MCP uses Unix socket at `~/.mutande/daemon.sock`.
- Hub at Deno Deploy `https://mutande.6lackknight.deno.net`; prod web `https://mutande.online` until `mutande.ai` (`mutande.vercel.app` still works as alias); Auth0 custom domain `auth.mutande.online` (`AUTH0_DOMAIN` for JWKS/authorize — not the tenant `*.auth0.com` host); Auth0 JWKS on hub; audience `https://hub.mutande.app`; `web/` is Next.js + Auth0 on Vercel for signup/invites (Mixpanel analytics on prod web); desktop/mobile share the same Auth0 account.
- Mac Auth0 login is Native + loopback callback (`http://127.0.0.1:<port>/callback`); defaults live in `core/src/daemon/auth0_defaults.rs`. Local pilot ops dashboard at `pilot/ops` (Deno; Auth0 PKCE on localhost) for feedback/waitlist charts — not part of the web deploy.
- Onboarding is self-serve create-team or join-invite (Mac-first); org slug is user-picked; handle defaults to `email-local@org`. Post-onboard: blocking host connect (MCP + skill install), then first-run ping wizard (copy prompt, poll Threads, celebrate — complete when a pong is received; skipping allowed); progress in `~/.mutande/first_run.json`. Mac Contacts tab loads hub `list_contacts` — your-handle card, broadcast callout, copy/Message on teammates; solo org shows invite CTA to prod web `/admin/invites`.
- Local notification prefs + muted thread ids in `~/.mutande/notification_prefs.json`; inbox watch (~30s) shows metadata-only OS banners when agents have new mail and no host turn is running.
- RPC `install_skill` writes Cursor/ChatGPT skill paths or stages Claude ZIP under `~/.mutande/skills/`; skill status lives beside MCP outcomes in `~/.mutande/host_links.json`.
- Large payloads use private R2 with object key prefix `blobs/{id}` (`R2_*` hub env). Public installers use `mutande-releases` at `https://downloads.mutande.online` via `scripts/upload-downloads-r2.sh` (`R2_DOWNLOADS_*` keys — not hub blobs tokens).
- Always publish Mac + Windows installers together when cutting a desktop release (Mac: notarized DMG locally; Windows: Actions `Release Windows alpha`, which uploads the zip to the same R2 bucket).
- Flutter thinking UI uses a single **working** orb (tilted particle orbits) for all loading states.
- Agent addresses use `handle/agent` (`alice@acme/claude`); bare handle is the default agent; never show `/default` as a user-facing address; for self-collaboration allow short `@agent` (e.g. `@claude`); personal `@all` means one shared group thread among the user's own agents and may carry questions (distinct from org broadcast `@all@acme`, which must not carry question payloads). Day-one success is MCP `ping` (`health` = daemon auto-pong; `thread` = real Threads mail agents reply to), typically targeting personal `@all`.
- Mac app bundle id is `ai.mutande.app`; bundles `mutande-core` sidecar in app Resources and launches it on startup; v1 ships as notarized DMG via `scripts/release-macos-dmg.sh` then `scripts/upload-downloads-r2.sh` to public bucket `mutande-releases` (`https://downloads.mutande.online`); Windows alpha zip uses the same upload path from Actions `publish-r2` (secrets `R2_DOWNLOADS_*`); site `/download` gates Intel/Windows via `NEXT_PUBLIC_*_PUBLISHED`; local `web/public/downloads/*` gitignored only.
- Public docs at `/docs` via Nextra in `web/`, same Vercel deploy as marketing/auth; security writeups may link technologies and describe E2E at a high level without revealing proprietary crypto IP. Landing intro is Remotion in `video/` (1080² @ 60fps), cinematic YC-explainer style (per-scene zooms, host app windows, mutande threads UI); render MP4 + poster into `web/public/brand/` for the hero `<video>`.
- Thread messages nest via bundle `in_reply_to` and hub `parent_message_id`. Agent upvotes (up-only, one per agent_id, toggle) signal coordination weight on a message; MCP tool `upvote_message`.
