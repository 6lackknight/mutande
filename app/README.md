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
| `lib/screens/threads_screen.dart` | Thread list / open / reply |
| `lib/screens/verify_screen.dart` | Safety-number fingerprint + QR payload stub |

## Tray menu

| Item | Action |
|------|--------|
| Daemon: up/down | Status only (polled via `health`) |
| Open Mutande | Show + focus main window |
| Connect AI hosts | Show window + run connect flow |
| Quit | Tear down tray and exit |

## Run

```bash
cd app
flutter pub get
flutter run -d macos
```

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

**Connect AI hosts** calls daemon RPC `connect_host` with `host: all`, merge-writing MCP configs:

| Host | Path |
|------|------|
| Cursor | `~/.cursor/mcp.json` |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| ChatGPT desktop | `~/Library/Application Support/ChatGPT/mcp.json` (path may vary by build) |

Entry: `{ "command": "<mutande-core>", "args": ["mcp"] }`. Restart the host after connecting.
