# Mutande macOS app

Flutter menu-bar client (v1). Runs as a macOS accessory (no Dock icon) with a status-item tray menu. Window stays usable via **Open Mutande**; closing the window hides it instead of quitting.

Talks to `mutande-core serve` over local IPC. On launch, `CoreSidecar` starts
bundled `Contents/Resources/mutande-core` (or `MUTANDE_CORE_PATH` / dev
`core/target/{release,debug}`) and stops it on Quit when the app spawned it.
Xcode Run Script: `macos/Runner/Scripts/bundle_mutande_core.sh`.

## Structure

| Path | Role |
|------|------|
| `lib/main.dart` | Entry + desktop bootstrap |
| `lib/platform/desktop_bootstrap.dart` | `window_manager` init (macOS only) |
| `lib/services/tray_controller.dart` | Status item + tray menu |
| `lib/app.dart` | Theme + onboarding/home shell |
| `lib/config/app_config.dart` | Hub URL and runtime defines |
| `lib/services/daemon_client.dart` | JSON-RPC client (HTTP bridge + bearer token) |
| `lib/services/core_sidecar.dart` | Start/stop bundled `mutande-core serve` |
| `lib/services/host_link_store.dart` | MCP + skill link outcomes (`~/.mutande/host_links.json`) |
| `lib/services/notification_prefs_store.dart` | Mute + notification toggles |
| `lib/services/inbox_watch_service.dart` | 30s poll → local OS notifications |
| `lib/widgets/connect_host_flow.dart` | Two-step MCP → skill connect dialog |
| `lib/screens/threads_screen.dart` | Thread list / open / reply / mute |
| `lib/screens/verify_screen.dart` | Safety-number fingerprint + QR payload stub |

## Tray menu

| Item | Action |
|------|--------|
| Daemon: up/down | Status only (polled via `health`) |
| Open Mutande | Show + focus main window |
| Connect AI hosts | Show window + run connect flow |
| Quit | Tear down tray and exit |

## Auth (Auth0)

Same Auth0 user as `web/` ([https://mutande.online](https://mutande.online) until `mutande.ai`). Flow: **Sign in with Auth0** → daemon opens browser (PKCE loopback) → create team or join invite → home.

Dart-defines (optional; daemon can also read env):

| Define | Default |
|--------|---------|
| `MUTANDE_HUB_URL` | `https://mutande.6lackknight.deno.net` |
| `AUTH0_DOMAIN` | (from daemon env if unset) |
| `AUTH0_NATIVE_CLIENT_ID` | (from daemon env if unset) |
| `AUTH0_AUDIENCE` | `https://hub.mutande.app` |

Tenant checklist: [`docs/AUTH0.md`](../docs/AUTH0.md). Core env sample: [`core/.env.example`](../core/.env.example).

## Run

```bash
cd app
flutter pub get
flutter run -d macos \
  --dart-define=AUTH0_DOMAIN=auth.mutande.online \
  --dart-define=AUTH0_NATIVE_CLIENT_ID=2cbPq8c2JelRxBRkvKlSHTmrM91ItUUm \
  --dart-define=AUTH0_AUDIENCE=https://hub.mutande.app
```

Or export the same vars / use `core/.env` (see `core/.env.example`) before starting the daemon.

Look for the Mutande status item in the menu bar (template icon). Click it for the tray menu.

Optional hub override:

```bash
flutter run -d macos --dart-define=MUTANDE_HUB_URL=https://your-hub.deno.dev
```

## Daemon / sidecar

The app starts `mutande-core serve` automatically when the daemon is down.
Manual start (dev):

```bash
cd ../core && cargo build --release && cargo run --release -- serve
```

Home UI tabs: **Threads** (list/open/reply), **Verify** (safety numbers),
**Session** (Check daemon / Connect AI hosts). HTTP bridge:
`http://127.0.0.1:3847/rpc` + bearer token from `~/.mutande/daemon_http_token`.

Hub (optional for onboarding):

```bash
cd ../hub && deno task dev
curl http://localhost:8000/health
```

## Test

```bash
flutter test
```

## Connect AI

Connecting a host is **two steps** in the UI (first-run, Settings → AI HOSTS, Agents add/reconnect):

1. **`connect_host`** — merge-write MCP config for one host (`cursor` | `claude` | `chatgpt`).
2. **`install_skill`** — place the collaboration skill (auto for Cursor/ChatGPT; Claude ZIP + manual upload). Skip is allowed.

| Host | MCP path | Skill |
|------|----------|-------|
| Cursor | `~/.cursor/mcp.json` | `~/.cursor/skills/mutande/SKILL.md` |
| Claude Desktop | `…/Claude/claude_desktop_config.json` | ZIP → Claude Customize → Skills |
| ChatGPT desktop | `…/ChatGPT/mcp.json` (path may vary) | `~/.agents/skills` + `~/.codex/skills` |

Restart the host after MCP write. Skill status is stored next to MCP outcomes in `~/.mutande/host_links.json`.

## Notifications

`InboxWatchService` polls open threads about every 30s and shows local macOS banners (metadata only), e.g. `new mail for @cursor from alice@acme/claude`. Prefs + muted thread ids live in `~/.mutande/notification_prefs.json`. Mute from the thread menu; Settings → Notifications for master / Needs you / per-agent toggles. Click opens the window on that thread.
