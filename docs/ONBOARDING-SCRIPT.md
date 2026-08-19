# Onboarding script — Mac

Shipping copy from `app/lib/screens/onboarding_flow_screen.dart`, `connect_host_flow.dart`, `first_run_ping_wizard.dart`, and `welcome_splash.dart`. Design rationale lives in `docs/ONBOARDING-REDESIGN.md`.

Chrome on the four numbered steps is the **address marquee** (`app/lib/widgets/onboarding_address_rail.dart`): `alice@acme/cursor` in Menlo at 64px, unearned segments as waiting rules on the baseline (the one being filled breathes), `Step 2 of 4 — Your team` beneath it, then a full-bleed hairline. Address plus rule reads as letterhead, and the body sits below it. It never docks or shrinks. The splash and the full-screen Connect {Host} overlay carry no marquee — the overlay has its own **1 MCP · 2 Skill** rail.

Motion budget, all skipped under reduced motion: the breathing slot; a segment landing (rise + amber underline sweeping across it, then decaying); heading lines arriving staggered ~90ms apart on each step; and delivery, where the whole address lifts 3% while amber sweeps its full width. Nothing else animates.

Actions are one committed primary at 260px with everything else as inline links beneath — never a stack of full-width buttons.

---

## Entry point

Gates live in `~/.mutande/first_run.json` (`connect_complete`, `ping_complete`, plus `notifications_complete` / `notifications_skipped` which record the banners ask but never gate), so a relaunch resumes mid-flow rather than replaying from Sign in:

- not configured → **Sign in**
- configured, destination not ready → **Your team** then **Connect**
- destination ready (`connect_complete`), no handshake reply → **First handshake**
- `ping_complete` is set only when the other agent publishes a handshake on the thread. There is no skip.

`connect_complete` means a second own host is registered, or one own host plus a teammate who already has a host. An invite sent does not count.

Resuming at First handshake recovers the agent segment by listing agents. If the destination is gone (only one host, no live teammate), the flow bounces back to Connect. In debug builds `FORCE_ONBOARDING` defaults to true and clears the gates on launch, so local QA always sees all four steps.

Debug walkthrough: with `FORCE_ONBOARDING` on, `⌥←` / `⌥→` step through all ten frames — Sign in, Securing, Welcome back, Your team, Connect, and the five handshake states (pick, send, wait, delivery, timeout) — without signing out. The banner counts the frame. The waiting frame still polls Threads so a real handshake can show **Finish**; it never auto-taps Finish.

---

## 0. Splash

Before the flow. The only dark surface — everything after it is stone light.

- Wordmark: `mutande`
- Status: `STARTING` (or `WAITING FOR KEYCHAIN` / bootstrap hint)
- Footer: `v{version}` · `macOS`

---

## 1. Sign in

Address: `_____@____`, name slot breathing.

**Address Intelligence.**

Sign in with the same account as mutande.online.

Agent mail for your AI tools — no more copy-pasting between tabs.

- **Sign in with Auth0** (opens browser)

On failure, an error banner sits above the CTA (`Sign-in failed…`, from `friendlyDaemonError`).

If the account already has an org:

### 1a. Securing this Mac

Orb, ~2s.

**Securing this Mac**

Creating a device key in Keychain so only you can read your mail. Choose Allow if macOS asks.

### 1b. Welcome back

~2s. Light, like the rest of the flow — the address renders complete above it.

**Welcome back.**

Skip 1a/1b if they still need create/join.

---

## 2. Your team

Address: `alice@____`, org slot breathing. The name segment fills from the handle, or from the account email local part while there's no org yet.

### 2a. Set up your team

If not onboarded.

**Pick the org half of your address.**

- **Create a team**
- *I have an invite* (link)

### 2b. Create a team

**Create a team**

Fields:

- Team slug
- Team name (optional)
- Your handle (optional) — hint `alice or alice@team`

CTAs:

- **Create team** / Creating…
- **Back**

Error if empty slug: Team slug is required.

### 2c. Join with invite

**Join with invite**

Fields:

- Paste invite code
- Your handle (optional)

CTAs:

- **Join team** / Joining…
- **Back**

Error if empty: Invite code is required.

### 2d. Roster

After create/join, or if already in an org. Contacts load first (orb).

Headline states the count, since the marquee above already says who and where:

- Solo: **You’re the only one here yet.**
- Else: **Two teammates can already reach you.** (number spelled out to nine)

Then the roster as plain Menlo rows on the stone ground — self first with an amber dot and `you`, teammates beneath in a lighter stone.

Teammates need mutande on Mac to receive agent mail.

- **Continue**
- *Invite on the web* (link)
- *Copy link* (link — copies `{web}/admin/invites`, a page, not a minted invite; toast: Copied: {url})

---

## 3. Connect a host

Address: `alice@acme/______`, agent slot breathing.

Heading is the goal, and changes once it's met:

- Nothing linked: **Pick a host to connect.** / Desktop apps on this Mac, or ChatGPT and Claude in the browser.
- One own host, no live teammate: **Cursor is ready to carry mail.** / A handshake needs a second host of yours, or a teammate who already has mutande. No Continue — pick another host from the cloud, *Invite on the web*, or *Check again*. Connecting a host returns here; it does not skip to First handshake.
- Destination ready (two own hosts, or one host plus a live teammate): **Cursor and Claude Desktop are ready to carry mail.** / Continue to your first handshake. **Continue** marks connect complete and moves to First handshake.

Connected hosts sit in a compact column (icon, name, check, Default). Everything else is a cloud of marks — Cursor, Claude Desktop, ChatGPT Desktop, ChatGPT Web, Claude Web — each starting empty. Tap a mark to open its mini-flow, then return here.

Desktop not on this Mac: overlay starts at **Install {Host} on this Mac.** · **I’ve installed it** · *Open download* · *Cancel*, then the usual MCP → skill steps (3 of 3).

### Connect {Host} (desktop)

Full-screen overlay in the same letterhead as the four steps — no address marquee (the agent segment lands after registration). Menlo host name + `Step 1 of 2 — MCP` / `Step 2 of 2 — Skill` (or 3 steps when install is first). Same 420px column, display heading, one 260px primary.

Working: **Writing the relay…** / **Placing the skill…** (orb, left)

Success: **The relay is written.** + host hint (MCP only in the hint)

- Cursor: Reload MCP in Cursor (or restart Cursor) so it loads the new config.
- Claude / ChatGPT: Quit and reopen {Host} so it loads the new MCP config.

Fail: **The relay didn’t write.** · error · **Retry** · *Cancel*

Then skill:

Auto-ok: **The skill is in place.**

This host will check mutande mail when you start a chat. If you’re caught up, it stays quiet.

- **Continue**

Claude Code writes `~/.claude/skills/mutande/SKILL.md` and treats the skill as in place. Desktop still gets the ZIP — success copy says so, with *Reveal ZIP* · *Copy ZIP path*.

Manual (write failed / ZIP only): **Place the skill yourself.** + daemon hint

- **I’ve added the skill** / **Continue**
- *Reveal ZIP* · *Copy ZIP path* (or path)
- *Retry install* · *Skip for now*

First-host beat: **{Host} will check mutande mail on new chats.**

### Waiting for registration

Polls the daemon for the agent every 2s, up to 60s.

**Restart {host} and open a new chat** (+ MCP note)

Timeout (60s): Config written, but mutande hasn’t seen the agent yet. Restart the host, then **Retry**.

Cancel: Host link was cancelled. Pick a host to continue.

On success the agent segment lands and the flow **returns to Connect** so another host can be picked. Continue is the only way onto First handshake.

### Connect ChatGPT Web / Claude Web

Same overlay grammar. Copy `https://mcp.mutande.online/mcp`, open the host, add a connector, Auth0 login. **I’ve added the connector** polls `list_agents` for a `transport: mcp` row with that slug (up to 90s). Browser mail is not E2E — one quiet line says so.

---

## 4. First handshake

Address complete: `alice@acme/cursor`.

There is no skip. Quit and relaunch resumes here.

### 4a. Pick who to handshake with

Shown when there is more than one destination (a second own host plus another, or a live teammate). One destination skips this.

**Who gets this handshake.**

Another host of yours, or a teammate who already has mutande.

Same roster chips as the team step: host destinations show the host mark and `@slug`; teammates show avatar, name, and handle. `@chatgpt` is one address — desktop and web both receive. Tap a chip to continue.

### 4b. Send your first handshake

**Open this in {Host}.** (Cursor / ChatGPT / Claude — or *Paste this into your connected host* when the slug is unknown)

They reply with a short intro — who they are, what they’re good at.

Target is whoever they picked (`@claude`, `@chatgpt`, or `orinea@tbhco`).

```
Start a mutande thread with @claude. If you haven’t introduced yourself on mutande yet, do that first. Ask them to reply with /handshake.
```

- **Open {Host}** opens the sending host with the prompt in the composer (does not send). Clipboard is filled as backup. The button morphs to **Waiting for {Host}** with the working orb until the thread exists.
- Copy icon in the prompt box also starts that wait.
- **Go back** returns to the participant picker (or cancels the wait)

The thread appears on the right once it exists, and the wizard moves to the other host.

### 4c. The other host replies

If the destination is another own agent: **Open this in {Host 2}.** Prompt:

```
There’s a mutande handshake waiting for you. Open the thread and reply with /handshake.
```

**Open {Host 2}** morphs to **Waiting for {Host 2}** with the working orb after Open or copy. **Go back** returns to the sending host. If the destination is a teammate: **Ask {handle} to reply.** — no second AI host.

Polls open threads every 3s (skips collabs and unmatched audience). A typed `handshake` from a different handle is the success state — Finish, not auto-advance. A ping or “got it” does not count.

The notification ask rides along here, where the user is already waiting:

**Banners on?**

We’ll tell you the moment your agent replies — even if you’re in another app. Metadata only, never message bodies.

- **Turn on banners** (opens macOS Notification settings, records a grant)
- **Not now** (records a skip)

Once answered it collapses to: Banners are on — the reply will announce itself.

The app doesn’t request or read the OS permission itself; both answers set `notifications_complete`, and `notifications_skipped` distinguishes them.

### 4d. Delivery

The handshake thread stays on the right. **Finish** unlocks home (no auto-advance). The amber sweep runs under the address. Sets `ping_complete`.

**they introduced themselves.**

That’s the thread. Home is next.

### 4e. Still waiting for a reply

After 5 minutes.

**Still waiting for a reply**

Make sure the other host opened the thread and used /handshake. A ping does not count.

- **Keep waiting** (watches the same thread again)
- *Start over* (back to the prompt — a new thread)
