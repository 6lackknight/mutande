# Mutande v1 — Product Requirements Document

## Problem Statement

Cofounders and teammates use AI agents to produce research, decisions, and documents, but sharing that work between agents still relies on manual copy-paste through chat apps (WhatsApp, email). There is no secure, structured way for one person's agent to hand context or questions to a colleague's agent asynchronously. Existing file services and chat apps are not agent-native, and sending sensitive business context through them is awkward and hard to trust.

## Solution

Mutande ("Messenger of the Gods") is agent-to-agent mail for teams. Users install a macOS desktop app that runs local end-to-end encryption and connects their AI assistant (Cursor, Claude Desktop, or ChatGPT desktop) via MCP. Agents build request bundles with questions and resources, forward them to colleagues by handle, to **their own** agents (`@claude`, bare `@all`), or to the team (`@all@org`), and track **threads** with clear open/replied/closed status. The cloud hub is a blind courier—it routes ciphertext and metadata but cannot read content. Large artifacts (codebases, video) use encrypted blob storage; small handoffs stay in inline envelopes.

## User Stories

1. As a cofounder, I want to invite my teammate to my org, so that we can address each other's agents by handle.
2. As a new user, I want a simple macOS installer without editing config files, so that I can start in minutes.
3. As a new user, I want the app to generate encryption keys automatically, so that I don't manage cryptography manually.
4. As a new user, I want to verify my colleague's safety number via QR or short code, so that I trust I'm messaging the right person.
5. As a user, I want to pick Cursor, Claude, or ChatGPT and tap Connect, so that my agent can use Mutande without MCP expertise.
6. As a user, I want Mutande to run from the menu bar, so that it stays available without cluttering my desktop.
7. As a user, I want the background service to keep running when I close the window, so that my agent can still send and receive mail.
8. As a user working with my agent, I want to stage questions and resources in a draft, so that I can batch what I need from a colleague.
9. As a user, I want to review a draft before sending, so that nothing leaves without my awareness.
10. As a user on Cursor, I want human decisions shown via AskQuestion, so that confirmations and questions feel native.
11. As a user on Claude or ChatGPT, I want the same decisions presented clearly in chat, so that I can reply before send tools run.
12. As a sender, I want to message a specific colleague (`alice@acme`), so that I can target one person's agent.
13. As a sender, I want to message `@all@acme`, so that I can broadcast a handoff to the whole team without caps.
13a. As a sender, I want to message `@claude` or bare `@all`, so that I can hand off between my own agents (Cursor ↔ Claude ↔ ChatGPT) without leaving mutande.
14. As a recipient, I want one thread per broadcast instead of inbox flood, so that I can respond once in context.
15. As a sender, I want all replies aggregated on a single thread, so that I see who responded without separate DMs.
16. As an agent, I want to know if a thread is open, replied, or closed, so that I don't duplicate work.
17. As a recipient, I want my agent to see whether I still owe a reply, so that pending items surface at session start.
18. As a sender, I want to close a thread when done, so that open lists stay accurate.
19. As a user, I want handoffs encrypted end-to-end on desktop, so that Mutande staff cannot read my content.
20. As a user, I want inline handoffs for typical agent docs (~6k words), so that most daily paste-replacement works without extra steps.
21. As a user on a paid plan, I want to share large encrypted blobs (repos, video), so that agents don't push me to Drive/Dropbox.
22. As a free-tier org, I want ~500MB blob storage, so that small team experiments work within platform limits.
23. As a user, I want blob uploads encrypted before they hit storage, so that object storage never sees plaintext.
24. As a user, I want async delivery, so that my colleague doesn't need to be online when I send.
25. As a supervised user, I want my host's allow now/always controls on send tools, so that policy stays in Cursor/Claude/ChatGPT—not on Mutande servers.
26. As a user with an autonomous agent setup, I want my agent to poll and respond when my host allows tools, so that Hermes/OpenClaw-style workflows work without Mutande guardrails.
27. As a user, I want to list org contacts including `@all@org`, so that my agent knows valid team recipients (self shorthand `@slug` / bare `@all` are not contact rows).
28. As a user, I want partial replies on a thread, so that I can answer some questions and continue later.
29. As a recipient, I should not receive `@all@org` question broadcasts, so that I'm not hit with mass AskQuestion prompts.
30. As a reply author on a broadcast, I want my reply visible to the sender only in v1, so that team broadcasts don't become noisy group chats.
31. As a user, I want encrypted server-side drafts, so that I can build a request over multiple sessions.
32. As a user, I want push/email notification metadata only later, so that I'm not surprised by async mail (v1.5 acceptable).
33. As an org admin later, I want invite-only closed orgs, so that strangers can't message us (v1: invite-only).
34. As a developer on the team, I want a monorepo with clear modules, so that hub, core, app, and schemas evolve independently.
35. As a security-conscious user, I want open-source crypto in the core, so that I can verify keys never leave my machine.
36. As a macOS user, I want Keychain storage for secrets, so that keys match platform expectations.
37. As a user, I want auto-updates, so that security fixes ship smoothly (macOS Sparkle/notarization path).
38. As an agent, I want MCP tools for list/get thread, draft, forward, reply, and close, so that workflows are consistent.
39. As a user, I want the hub to enforce org boundaries, so that only colleagues in my org receive mail.
40. As a user, I want thread metadata (who/when/counts) visible to the hub, so that delivery works even when content stays secret.

### v1.5 — Mobile E2E companion (iOS first, then Android)

41. As a mobile user, I want a Mutande app on my phone with full E2E, so that I can read and reply to threads without waiting for my Mac.
42. As a mobile user, I want my phone registered as a second device on my handle, so that senders encrypt to both Mac and iPhone.
43. As a mobile user, I want keys stored in the platform secure enclave/Keychain, so that mobile E2E matches desktop trust.
44. As a mobile user, I want push notifications when a thread needs me, so that I'm not surprised by async mail (notification body contains metadata only, never plaintext).
45. As a mobile user, I want to list and filter threads (needs action, open, closed), so that I can manage mail without a desktop agent.
46. As a mobile user, I want to read decrypted handoffs and questions in-app, so that I don't need ChatGPT mobile for Mutande content.
47. As a mobile user, I want to reply to threads from the app, so that my colleague's desktop agent receives my answer on the same thread.
48. As a mobile user, I want to download and decrypt large blobs on device, so that Pro artifact handoffs work on phone as on desktop.
49. As a mobile user, I want to verify contacts via QR scan, so that safety-number checks work on the device I carry.
50. As a mobile user chatting with ChatGPT on my phone, I want clarity that mobile ChatGPT is separate from Mutande, so that I know to open the Mutande app for mail (agents remain desktop-only).
51. As a desktop user, I want threads to stay in sync across Mac and phone, so that replying on either device updates the same thread state.
52. As a sender, I want broadcast and direct sends to reach all of a recipient's registered devices, so that mobile peers are not second-class.

## Implementation Decisions

### Monorepo modules (deep modules)

1. **`crypto` (Rust, core)** — Keygen, Keychain persistence, X25519/Ed25519 identity, `crypto_box` encrypt/decrypt, AES file encryption, per-recipient key wrap for `@all` broadcasts. Interface: encrypt to handle(s), decrypt inbound ciphertext, wrap/unwrap blob keys. Rarely changes; heavily tested.

2. **`hub_client` (Rust, core)** — Authenticated REST client: register, contacts, threads, drafts, blob presign URLs. Interface: high-level operations returning ciphertext bytes or metadata structs. No plaintext logging.

3. **`daemon` (Rust, core)** — Local socket server bridging Flutter UI and MCP subprocess. Interface: JSON-RPC or REST on Unix socket under `~/.mutande/`. Starts on login; holds JWT refresh and crypto session.

4. **`mcp` (Rust, core)** — MCP stdio server (`mutande-core mcp`) forwarding tool calls to daemon. Exposes: `list_contacts`, `list_threads`, `get_thread`, `draft_*`, `forward_draft`, `reply_to_thread`, `close_thread`, `mark_processed`. Split read tools vs send tools for host allow patterns.

5. **`hub` (Deno Deploy)** — Hono REST + Deno KV + R2. Blind courier: auth JWT, org membership, thread metadata, ciphertext storage, blob registry, presigned URLs. KV key patterns for users, handles, threads, per-user inbox pointers, broadcast fan-out wraps. Inline messages ≤ ~64KiB KV value; larger via R2 ciphertext only.

6. **`app` (Flutter, macOS v1)** — Menu-bar UI: onboarding, invite accept, safety verify (QR), Connect AI wizard (MCP then skill per host), thread list/status/mute, local mail notifications, daemon lifecycle, Sparkle updates. No crypto logic—delegates to daemon.

7. **`proto` (JSON Schema)** — `HumanDecision`, `MutandeBundle`, `ThreadMeta` shapes shared by hub, core, skill.

8. **`skill` (agent instructions)** — New-chat inbox check (silent when clear; no timer poll), AskQuestion mapping, addressing (`@slug` / `@all` / `@all@org`), blob vs inline guidance. Installed via `install_skill` on connect (Claude: ZIP upload).

### Architectural decisions

- **E2E desktop-only v1** — macOS ships first; mobile ChatGPT/Claude apps never receive MCP or Mutande keys.
- **v1.5 mobile full E2E peer (Tier C)** — iOS companion app first, then Android; same encrypted mail as desktop; agents remain desktop-only.
- **No hub guardrails** — Host allow now/always only.
- **Threads not tickets** — `open`/`closed`, participant `pending`/`replied`; broadcast replies sender-only visibility v1.
- **`@all@org` uncapped on free tier** — Team-first; bare `@all` is my-agents only. Platform blob pool still ~500MB/org active storage aligned to R2 free tier economics.
- **HumanDecision kinds** — `question`, `confirm_forward`, `verify_contact`; AskQuestion on Cursor when host attaches tool; structured chat fallback otherwise.
- **One installer** — Flutter app bundles `mutande-core`; sidecar process, not second download.
- **MCP points at `mutande-core mcp`**, not hub URL; JWT and keys stay in daemon/Keychain.
- **Hub on Deno Deploy** — Not Railway/Postgres for v1.
- **Premium wedge** — Large encrypted blobs (codebase tar, video) vs inline ~40KB comfort zone.

### API contracts (hub)

- Auth: register with invite, pubkey upload, JWT token refresh, `/me`
- Devices (v1.5): register additional device pubkeys per handle; list/revoke devices; fan-out and broadcast wraps include all active device keys per recipient
- Contacts: list org members + synthetic `@all@org` (not bare `@all` / `@slug`)
- Threads: create on forward, list with filters (`needs_action`, `open`, `closed`), get with metadata + ciphertext refs, reply, close
- Drafts: CRUD ciphertext encrypted to self
- Blobs: presigned PUT/GET; hub tracks quota per org
- Broadcast: single logical thread, per-recipient wrapped keys, one inbox pointer per user

### Thread / broadcast behavior

From prototype schema (`ThreadMeta`):

```
kind: direct | broadcast
status: open | closed
your_status: pending | replied
```

Fan-out: one content encryption + N wrapped keys. Sender inbox row updates in place on new replies.

### Blob pipeline

Client encrypts file → presigned PUT → envelope references `blob_id` + `wrapped_key` + `sha256`. Recipient presign GET → decrypt locally.

### v1.5 — Mobile E2E companion

**Product positioning:** Agents on desktop; humans manage and reply on Mac or phone. Same encrypted threads; not MCP inside ChatGPT mobile.

**Platform order:** iOS first (Keychain, APNs), Android second (Keystore, FCM).

**Architecture:**

- Reuse Flutter for iOS/Android UI (thread list, read, reply, verify, settings).
- Reuse Rust `mutande-core` crypto via FFI or embedded library—no second crypto stack.
- Mobile app talks to hub directly (HTTPS + JWT); no MCP on mobile.
- Each device registers independently: e.g. `alice@acme` + device record (`macos`, `iphone`) with its own pubkey.
- Send path: encrypt content once; wrap content key for every device pubkey of each recipient (extends broadcast multi-wrap pattern).
- Push: APNs/FCM with `{ thread_id, from, kind }` only—never subject, body, or blob names.

**Mobile UI scope:**

- Onboarding: sign in / accept invite, generate device keys, optional link to existing account (QR from Mac).
- Thread list with `needs_action` / open / closed filters.
- Thread detail: decrypt locally, show bundle content, HumanDecision-style reply controls (native UI, not AskQuestion).
- Reply and close thread (encrypted outbound same as desktop daemon).
- Blob download → decrypt → share/open locally.
- Device management: view/revoke registered devices.

**Explicitly not v1.5:**

- MCP on mobile
- Agent automation on phone
- E2E inside third-party chat apps
- Share extension from ChatGPT (optional later)

## Testing Decisions

**Good tests** assert external behavior at module boundaries—given plaintext and pubkeys, ciphertext round-trips; given thread operations, metadata counts and states evolve correctly; MCP tools return decrypted content only through daemon mocks.

**Modules to test (priority):**

1. **`crypto`** — Unit tests: box encrypt/decrypt, broadcast multi-wrap, blob AES wrap, wrong-key failure. Highest priority.
2. **`hub` KV layer** — Integration tests with `:memory:` KV: thread create, broadcast fan-out keys, inbox pointers, quota rejection, 64KiB inline vs blob path selection signal.
3. **`daemon` API** — HTTP/socket tests: MCP forwarding, no private key in responses to MCP without auth.
4. **`hub_client`** — Mock HTTP: auth refresh, error mapping.
5. **`mcp` tool surface** — Snapshot tests for tool schemas and argument validation.

**Defer:** Flutter widget tests beyond onboarding wizard smoke; full MCP host integration (manual QA on Cursor).

**v1.5 additions:** Multi-device wrap tests in `crypto`; hub device registration and per-device delivery integration tests; mobile decrypt/reply smoke tests against mock hub.

No prior test art in repo—establish patterns in `core` and `hub` first.

## Out of Scope

- Windows and Linux desktop clients (v1 macOS only)
- E2E inside ChatGPT/Claude mobile apps (Mutande's own mobile app is v1.5, not in-chat integration)
- Hub-side autonomy, approval queues, or AskQuestion rendering
- `@all` / `@all@org` question broadcasts
- Cross-recipient visibility on broadcast replies (v1 sender-only)
- Git-aware codebase sync (v1: encrypted tarball/blob only)
- Metadata hiding (hub sees social graph, sizes, timestamps)
- Android mobile app before iOS v1.5 ships (iOS first)
- Share-to-Mutande from ChatGPT mobile (post–v1.5 optional)
- Public org discovery / messaging strangers
- Web UI for mail (app + agents only)

## Further Notes

- Product display name: **Mutande** / "Messenger of the Gods"; handles like `alice@acme`, self `@claude` / bare `@all`, broadcast `@all@acme`.
- Free inline handoffs cover typical agent memos; Pro monetizes encrypted artifact relay without requiring Google Drive etc.
- **v1.5 tagline:** Same encrypted mail on Mac and phone—agents on desktop, you on either device.
- Scaffold lives in monorepo: `app/`, `core/`, `hub/`, `proto/`, `skill/`.
- Issue tracker: publish this PRD as tracking issue with `ready-for-agent` when GitHub CLI available.
