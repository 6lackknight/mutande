# Inbox events — daemon push to Flutter (WebSocket / SSE)

## Problem Statement

The macOS app keeps the Threads tab feeling current by polling `list_threads` every three seconds while that tab is open. Each poll can trigger hub fetches and per-thread decrypt/enrichment work in mutande-core. We added stale-while-revalidate caches so the UI can paint instantly, but the app still wakes the courier on a fixed timer—wasteful when nothing changed, and still latency-bound when mail arrives between polls.

Users expect chat-like responsiveness: new thread rows and “Needs you” updates should appear within a second or two of delivery, without the list going blank or showing a loading orb while crypto runs. Encryption must not regress the UX, but polling the entire inbox from Flutter is the wrong layer to solve freshness.

## Solution

mutande-core runs **one** background inbox watcher that polls the hub for lightweight thread metadata (`updated_at`, status, counts—no full decrypt loop on every tick when nothing moved). When the metadata fingerprint changes, the daemon **pushes** an event to connected UI clients. The Flutter app subscribes over a long-lived local connection, invalidates the thread list on `inbox_changed`, and silently refetches—still using the existing thread-list cache and enrichment cache so decrypt work is skipped when hub timestamps are unchanged.

Agents keep using MCP over the Unix socket (pull JSON-RPC unchanged). The menu-bar app stops owning inbox poll timers for the Threads tab; optional consolidation with OS notification watch is a follow-on inside the same watcher module.

## User Stories

1. As a macOS user on the Threads tab, I want new mail to appear within about a second of the hub having it, so that the inbox feels live without me switching tabs.
2. As a macOS user, I want the thread list to stay visible while fresh data loads, so that encryption work never blanks the UI.
3. As a macOS user, I want the app to stop polling the courier every three seconds when nothing changed, so that idle CPU and battery use stay low.
4. As a macOS user reopening mutande, I want the last-known thread list instantly from disk cache, then a single refresh when the daemon confirms inbox state, so that startup stays fast.
5. As a macOS user with the window open on Agents or Contacts, I want thread badges elsewhere to update when mail arrives, so that I do not have to visit Threads first to notice pending items.
6. As a macOS user, I want push events to carry no plaintext bundle content, so that E2E guarantees stay the same as today (metadata-only on the wire locally).
7. As a Windows user (future alpha), I want the same push channel over the HTTP bridge, so that I am not stuck with Flutter-side polling only.
8. As a developer, I want one hub poll loop in the daemon shared by UI subscribers, so that we do not multiply hub traffic per open tab or service.
9. As a developer, I want reconnect with exponential backoff when the daemon restarts, so that the UI self-heals after “Restart courier”.
10. As a developer, I want subscribe/unsubscribe lifecycle on the push connection, so that background tabs do not leak watchers.
11. As a user who mutes a thread, I want list refresh to respect existing mute prefs, so that push does not bypass notification settings.
12. As a user filtering Threads (All / Needs you / Open), I want push to trigger a refresh of the active filter, so that counts and rows stay consistent.
13. As an agent user via MCP, I want inbox behavior unchanged on the Unix socket, so that Cursor/Claude/ChatGPT tools are unaffected.
14. As a security-conscious user, I want the push endpoint authenticated like `POST /rpc`, so that other local processes cannot snoop inbox activity without the bearer token.
15. As a QA engineer, I want deterministic tests for “metadata unchanged → no client event” and “one thread `updated_at` bump → one event”, so that we do not spam the UI.
16. As a user on a slow hub, I want the daemon watcher to backoff when hub calls fail, so that offline mode does not hammer the network.
17. As a user, I want OS notification banners to reuse the same daemon watcher eventually, so that InboxWatch and Threads do not each poll independently.
18. As a mobile user (v1.5), I want the same event contract documented for a future iOS subscriber, so that we do not invent a second push shape later.
19. As an ops engineer, I want metrics/logs for watcher ticks, events emitted, and connected clients, so that I can diagnose “mail delayed” reports.
20. As a user closing the mutande window to the tray, I want the daemon watcher to keep running with at least one subscriber or a cheap idle mode, so that tray “new mail” state stays accurate.

## Implementation Decisions

### Transport: WebSocket primary; SSE acceptable; Unix socket push optional (Mac)

| Option | Pros | Cons |
|--------|------|------|
| **WebSocket** `GET /ws` on `127.0.0.1:3847` | Bidirectional (subscribe, ping, filter scope); works on Windows; same port as HTTP RPC; token in first frame or header | Slightly more code than SSE |
| **SSE** `GET /events` | Simple one-way notify; easy in Flutter via `http` stream | No native Windows story if we avoid long-lived HTTP on some clients; awkward subscribe params |
| **Unix socket push lines** | Lowest overhead on Mac; no HTTP token on FS-local IPC | Flutter does not use Unix socket today; Windows N/A |

**Decision:** Ship **WebSocket on the existing HTTP bridge** for v1 of this feature. Document an **SSE** endpoint as an equivalent one-way subset if we want browser/debug clients later. **Unix socket unsolicited notifications** are out of scope for v1 but should reuse the same event JSON shape when added.

### Deep modules

1. **`InboxWatcher` (core / daemon)**  
   - Single task started with daemon.  
   - On interval (default **5s**, configurable; faster than old 30s notification poll, slower than old 3s UI poll): hub `list_threads` metadata-only path—compare against last seen map of `thread_id → updated_at` (+ status/your_status if cheap from hub).  
   - Emits internal `InboxRevision { revision, changed_thread_ids }` when fingerprint differs.  
   - Backs off on hub errors (reuse hub_client retry patterns).  
   - Does **not** full-decrypt bundles on tick; enrichment still happens on client-driven `list_threads`.

2. **`EventHub` (core / daemon)**  
   - Fan-out bus: watcher + manual invalidations (e.g. after local `reply_to_thread`) → broadcast to subscribers.  
   - Tracks connected WebSocket clients, filter interest optional in v1 (default: any inbox change).

3. **HTTP WebSocket bridge (core / daemon)**  
   - Extends existing token-authenticated HTTP listener.  
   - After auth: client sends `{"op":"subscribe","channel":"inbox"}`.  
   - Server pushes:

```json
{"event":"inbox_changed","revision":42,"at":"2026-08-11T07:00:00Z"}
```

   - Optional later: `thread_changed` with `thread_id` for incremental UI.  
   - Ping/pong or application heartbeat every 30s; drop stale clients.

4. **`DaemonEventClient` (Flutter / app)**  
   - Connects to `ws://127.0.0.1:3847/ws` with bearer token from `~/.mutande/daemon_http_token`.  
   - Reconnect with backoff; exposes `Stream<InboxChangedEvent>`.  
   - Owned at app session level (not per-tab).

5. **Threads UI integration (Flutter)**  
   - Remove `_threadsPollInterval` timer when event stream connected.  
   - On `inbox_changed`: call existing `_reload(silent: true)` + update cache store.  
   - Fallback: if WebSocket disconnected > N seconds, resume slow poll (30s) until reconnected.

6. **Existing caches (unchanged contract)**  
   - Flutter `ThreadListCacheStore`: stale-while-revalidate.  
   - Core `thread_list_enrichment`: skip decrypt when hub `updated_at` matches.  
   - Push only changes **when** to refresh, not **how** decrypt works.

### Hub interaction

- Hub remains **pull-only**; no hub SSE in this PRD.  
- Watcher uses the same hub APIs `list_threads` already uses, ideally requesting only metadata the hub already returns in `ThreadMeta`.  
- If hub adds `ETag` / `If-Modified-Since` later, watcher switches to conditional GET (follow-up).

### Auth & security

- WebSocket upgrade requires same bearer / `X-Mutande-Token` as `POST /rpc`.  
- Events contain **no** decrypted snippets—only revision + timestamp.  
- Localhost-only bind unchanged (`127.0.0.1:3847`).

### Bootstrap / session gate

- Recent disk cache still allows fast Home entry.  
- WebSocket connect is best-effort after session ready; failure does not block Home.  
- First `inbox_changed` or successful `list_threads` confirms mail path.

### Proto / schema

- Add optional JSON schema under `proto/` for `InboxChangedEvent` and WebSocket client `subscribe` frame for cross-platform (iOS v1.5) alignment.

## Testing Decisions

**Principle:** Test externally visible behavior—event emitted or not, client refresh triggered—not internal timer implementation.

| Module | Tests | Prior art |
|--------|-------|-----------|
| `InboxWatcher` | Metadata fingerprint unchanged → no emit; one `updated_at` change → exactly one emit; hub error → backoff, no panic | `core` daemon unit tests, `thread_list_cache` tests |
| `EventHub` | Multiple subscribers receive same event; dropped client does not block others | `http_bridge` request tests |
| WebSocket bridge | Auth failure → close; valid subscribe → receive `inbox_changed` on watcher tick | `http_bridge.rs` integration tests with tokio |
| Flutter `DaemonEventClient` | Mock server sends event → stream fires; disconnect → reconnect | `daemon_client` / widget tests with mock HTTP |
| Threads screen | Event → silent reload called; WS down → fallback poll | `widget_test.dart` (disable orb settle loops) |

Widget tests: inject mock event stream; no real WebSocket in CI.

## Out of Scope

- Hub → daemon push (webhooks, KV watch, SSE from Deno Deploy)
- Pushing decrypted snippets or full thread bodies over WebSocket
- MCP Unix socket unsolicited notifications (separate PRD)
- Replacing agent skill `inbox-listen` / Cursor hooks
- iOS implementation (document contract only)
- Sub-second latency guarantees on free-tier hub cold starts
- Search tab live index updates (Threads tab first)
- Replacing `InboxWatchService` in the same slice (optional follow-up once watcher lands)

## Further Notes

- Display product name: **mutande** (lowercase in UI copy).
- Domain terms: **thread**, **bundle**, **handle**, **courier** (mutande-core), **hub** (blind courier).
- This PRD supersedes the Threads tab **3s poll** as the primary freshness mechanism once WebSocket ship is complete; keep a slow fallback poll for robustness.
- Tray status (`Daemon: up` / `starting`) stays tied to session + mail readiness, not WebSocket state.
- Align changelog entry with app + mutande-core version bump when shipping.
