# Mutande macOS app

Flutter menu-bar client (v1). Runs as a macOS accessory (no Dock icon) with a status-item tray menu. Window stays usable via **Open Mutande**; closing the window hides it instead of quitting.

Talks to `mutande-core serve` over local IPC. Bundles `mutande-core` binary in app resources (future).

## Structure

| Path | Role |
|------|------|
| `lib/main.dart` | Entry + desktop bootstrap |
| `lib/platform/desktop_bootstrap.dart` | `window_manager` init (macOS only) |
| `lib/services/tray_controller.dart` | Status item + tray menu |
| `lib/app.dart` | Theme + onboarding/home shell |
| `lib/config/app_config.dart` | Hub URL and runtime defines |
| `lib/services/daemon_client.dart` | JSON-RPC stub (HTTP dev bridge → Unix socket) |

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

## Daemon check

The home screen **Check daemon** button calls JSON-RPC `health` on `http://127.0.0.1:3847/rpc` with `Authorization: Bearer` from `~/.mutande/daemon_http_token` (written by `mutande-core serve`). Production uses `~/.mutande/daemon.sock` (see `daemon_client.dart` for the full method table from the PRD).

Start the core daemon:

```bash
cd ../core && cargo run -- serve
```

Start the hub locally for URL display sanity:

```bash
cd ../hub && deno task dev
curl http://localhost:8000/health
```

With `mutande-core serve` running, **Check daemon** should report connected.

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
