# Onboarding script — Mac

Shipping copy from `app/lib/screens/onboarding_flow_screen.dart`, `connect_host_flow.dart`, `first_run_ping_wizard.dart`, and `welcome_splash.dart`. Design rationale lives in `docs/ONBOARDING-REDESIGN.md`.

Chrome on the four numbered steps is the **address marquee** (`app/lib/widgets/onboarding_address_rail.dart`): `alice@acme/cursor` in Menlo at 64px, unearned segments as waiting rules on the baseline (the one being filled breathes), `Step 2 of 4 — Your team` beneath it, then a full-bleed hairline. Address plus rule reads as letterhead, and the body sits below it. It never docks or shrinks. The splash and the full-screen Connect {Host} overlay carry no marquee — the overlay has its own **1 MCP · 2 Skill** rail.

Motion budget, all skipped under reduced motion: the breathing slot; a segment landing (rise + amber underline sweeping across it, then decaying); heading lines arriving staggered ~90ms apart on each step; and delivery, where the whole address lifts 3% while amber sweeps its full width. Nothing else animates.

Actions are one committed primary at 260px with everything else as inline links beneath — never a stack of full-width buttons.

---

## Entry point

Gates live in `~/.mutande/first_run.json` (`connect_complete`, `ping_complete`, plus `notifications_complete` / `notifications_skipped` which record the banners ask but never gate), so a relaunch resumes mid-flow rather than replaying from Sign in:

- not configured → **Sign in**
- configured, no connected host → **Your team**
- connect done, no ping → **First ping**

Resuming at First ping recovers the agent segment by listing agents, so the address still reads whole. In debug builds `FORCE_ONBOARDING` defaults to true and clears the gates on launch, so local QA always sees all four steps.

Debug walkthrough: with `FORCE_ONBOARDING` on, `⌥←` / `⌥→` step through all nine frames — Sign in, Securing, Welcome back, Your team, Connect, and the four ping states including delivery — without signing out or waiting for a real pong. The banner counts the frame. In this mode the ping wizard never polls and never auto-completes.

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

- Nothing linked: **Pick a host to connect.** / One is enough — mutande wires the relay, then hands it the collaboration skill.
- Something linked: **Cursor is ready to carry mail.** (names joined with *and*, is/are) / Continue to your first ping, or connect another host. Plus a **Continue** primary that marks connect complete and moves to First ping without re-running the ceremony.

Each installed host is a full-width row — icon, name, status. Rows still to be connected end in an amber **Connect**; connected rows end in an emerald check (tap re-runs the connect flow). Anything not installed collapses into one quiet line beneath: `Claude Desktop and ChatGPT aren’t installed on this Mac.`

### Connect {Host}

Full-screen overlay in the same letterhead as the four steps — no address marquee (the agent segment lands after registration). Menlo host name + `Step 1 of 2 — MCP` / `Step 2 of 2 — Skill`, then the hairline. Same 420px column, display heading, one 260px primary.

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

Cancel: Host link was cancelled. Pick an installed host to continue.

On success the agent segment lands and the flow goes straight to First ping.

---

## 4. First ping

Address complete: `alice@acme/cursor`.

### 4a. Send your first ping

**Paste this into {agent}.** (or *your connected host* when the slug is unknown)

Your address takes it from there.

```
Use mutande to ping @all (thread)
```

- **Copy prompt** (toast: Copied — paste into your AI host)
- *I’ve pasted it — wait for pong* (link)
- *Skip for now* (link)

### 4b. Waiting for pong…

Your agent should call ping, then reply on the thread. This screen watches Threads.

Polls open threads every 3s (skipping threads with no activity in the wait window); completes when a `thread` ping has any reply.

The notification ask rides along here, where the user is already waiting:

**Banners on?**

We’ll tell you the moment your agent replies — even if you’re in another app. Metadata only, never message bodies.

- **Turn on banners** (opens macOS Notification settings, records a grant)
- **Not now** (records a skip)

Once answered it collapses to: Banners are on — the pong will announce itself.

The app doesn’t request or read the OS permission itself; both answers set `notifications_complete`, and `notifications_skipped` distinguishes them.

- **Skip for now**

### 4c. Delivery

~1.6s then home. The amber sweep runs under the address as this lands.

**received its first mail.**

Threads is where it lands from here.

### 4d. Still waiting for a pong

After 5 minutes.

**Still waiting for a pong**

Make sure your host ran ping and replied on the thread.

- **Retry**
- **Skip for now**
