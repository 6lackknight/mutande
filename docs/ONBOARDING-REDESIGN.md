# Onboarding redesign — your address, assembled

Design direction for Mac first-run. Companion to `docs/ONBOARDING-SCRIPT.md` (what ships today) and `pilot/ONBOARDING-DESIGN.md` (the pilot-locked decisions this revises).

**Shipped as Marquee.** Three variants were prototyped against the live copy — the address as a hero that docks after Sign in, the address as a permanent full-scale marquee, and the address as a quiet header marker with the drama in step headlines. Marquee won: the address holds the screen on every step and never shrinks. Implementation is `app/lib/widgets/onboarding_address_rail.dart` inside `OnboardingShell`.

## Decisions

| | Decision | Source |
|---|---|---|
| Intensity | Onboarding is **ceremony** — bold here, Threads/Home stay quiet courier | answered |
| Concept | **The address assembles**: `alice` → `alice@acme` → `alice@acme/cursor` → it receives its first mail | answered |
| Canvas | Splash is the **only** dark surface; everything after it is stone light | answered |
| Progress | The address **replaces** the 5-dot rail; ghosted empty slots show what's still missing | assumed — recommended |
| Type | Address set in **Menlo**, large — matches thread ids and the ping prompt; reads as a real typable address | assumed — recommended |
| Notify | **Folded into the ping wait** — asked while the pong is in flight, and the pong arrives as the first banner | assumed — recommended |

Consequence of the canvas answer: the dark **Welcome back** overlay goes light, and becomes the one screen where the address appears already complete.

## Why the current flow reads as safe

It's the same screen five times — left-aligned title, subtitle, a vertical stack of Filled/Outlined/Text buttons in a 560px column on stone50. Nothing signals that any step matters more than another. Supporting problems: tone flickers dark → light → dark → light in the first ten seconds; Notify opens with the templated 44px rounded-square icon beside its heading; the orb only ever plays spinner; **Pong received** — the day-one success moment of the whole product — gets 0.9s and a stock checkmark; and the address, which is the entire product frame, appears only as grey subtitle text.

## Five steps become four

Notify has no place in the address metaphor and was the step Roy flagged as easy to miss. Folding it into the ping wait fixes both: the ask lands while the user is already waiting with nothing to do, it's motivated ("we'll tell you the moment it lands") rather than abstract, and the arriving pong *proves* the permission works instead of the user self-attesting.

```
Sign in  →  Your team  →  Connect  →  First ping
 name        @org          /agent      delivery
```

## The address rail

Replaces `OnboardingStepper`. Menlo, three segments plus punctuation, always on screen after the splash.

- **Filled segment** — stone800, solid.
- **Empty segment** — a stone200 rule on the baseline at the width of the expected value. Not a run of underscores: at display size those weld into one redaction bar.
- **Active segment** — the one being filled; slow breath (stone200 ↔ stone400, 1.6s) so position is legible without a wizard rail.
- **Landing** — a value rises ~6px into place while an amber underline sweeps its width and then decays, 420ms. The waiting rule and the landing underline share a baseline offset, so the slot visibly becomes the word.
- **Caption** — one small stone400 line beneath: `Step 2 of 4 — Your team`. Explicit counting survives for the hand-holding Roy needed; it just isn't the visual furniture.

Scale: 64px on every step, top-left, never docking, with a full-bleed hairline under the caption — address plus rule reads as letterhead and gives the empty right side a job. The content column sits at 420px beneath it, which keeps the address the largest thing on screen throughout. It scales down only when a long handle would overflow the window.

Delivery: the address lifts 3% while an amber underline sweeps its full width over 620ms, ease-out-quart. No bounce, no confetti.

Headings: 30px, one substantive sentence rather than the step's name (the caption already names the step), lines arriving staggered ~90ms apart. Actions are one 260px primary with the rest as inline links — the stacked filled/outlined/text column made every step look like the same form.

## Screen by screen

### Splash — unchanged

The only dark surface. It now reads as a curtain: dark hold, then light for the rest of the flow.

### 1. Sign in

The empty address **is** the screen: `‗‗‗‗@‗‗‗‗` at 64px, left-aligned, sitting on generous top space. Headline drops to a supporting line beneath it, not above.

- Address: `‗‗‗‗@‗‗‗‗`
- Line: **Every agent you use, at one address.**
- CTA: **Sign in** (Auth0 is visible in the browser; the button doesn't need to name the vendor)
- Quiet under-CTA: Same account as mutande.online.

Error state keeps the existing banner above the CTA.

**Securing this Mac** stays as the post-browser interstitial with the orb — this is the one place the orb means something (the device key is being forged), so keep the copy factual and let the motion carry it.

**Welcome back** (already-configured accounts): light now, and the address renders complete and full-scale — `alice@acme` — with `Welcome back` beneath it. Two seconds, then Your team.

### 2. Your team

Address: `alice@‗‗‗‗`, org slot active. The name fills from the handle, or from the account email local part while there's no org yet.

Setup mode keeps create/join as-is. Roster mode loses the white bordered card — members become plain rows on the stone ground, which flattens a nested-container hierarchy that wasn't earning its box. `@acme` lands on **Continue**.

Fix riding along: **Copy invite link** currently copies `/admin/invites`, a page, not an invite. Either relabel to **Open invite page** or have the hub mint a real invite URL.

### 3. Connect

Address: `alice@acme/‗‗‗‗`, agent slot active.

Three equal host tiles are the identical-card-grid anti-pattern, and two of them are usually dead. Replace with hierarchy by detection state: **installed hosts get a large primary tile**, and anything not detected collapses into one quiet line — `Claude and ChatGPT aren't installed on this Mac` — rather than three tiles competing at equal weight.

Metaphor discipline in the sub-flow: it currently says "Linking the relay…" → "MCP linked." → "Relay linked", which is three names for one thing. Pick relay for everything the user reads, and let MCP appear only in the technical hint ("Reload MCP in Cursor so it loads the new config").

`/cursor` lands when the agent registers.

### 4. First ping

Address complete and docked. The prompt block is the hero.

Wait state carries the notification ask as its secondary action:

> **Banners on?** We'll tell you the moment your agent replies — even if you're in another app. Metadata only, never message bodies.
> **Turn on banners** · **Not now**

**Delivery** — the one celebration. The amber mark travels into the docked address, the address lifts to full 64px scale, and:

- `alice@acme/cursor`
- **received its first mail.**

Then the light transition into Threads. This is the moment worth a screenshot, and it costs no confetti.

## Motion budget

| Moment | Treatment | Duration |
|---|---|---|
| Active slot | Opacity breath, stone200 ↔ stone400 | 1.6s loop |
| Keychain wait | Existing orb | — |
| Delivery | Amber underline sweeps the address | 600ms |

Everything degrades to instant state change under `MediaQuery.disableAnimations`, and the breath is held still under `flutter test` so `pumpAndSettle` can finish.

## What died

The 5-dot stepper (and the `mutande` wordmark row above it). The 44px rounded-square amber bell beside the Notify heading. The white bordered card wrapping the roster. The three-equal-tiles host grid. The dark Welcome-back overlay. The separate Notify step. `first_run_connect_screen.dart`. The ping wizard's unused standalone (non-embedded) layout. "mutande won't treat config folders alone as installed" — engineering rationale in user copy.

## Loose ends

1. Window size: `pilot/ONBOARDING-DESIGN.md` says 1088×720, AGENTS.md says 1280×720. Going with AGENTS.md.
2. **Copy invite page link** still copies `/admin/invites`, a page rather than a minted invite — the label now says so, but the hub minting a real invite URL would be better.
3. Ping still requires leaving the app to paste a prompt. A host deep-link would close the last real gap; unresolved.

Closed on the way in: `notifications_skipped` now persists alongside `notifications_complete`, and the ping poll skips threads with no activity in the wait window instead of fetching every open thread every 3s.
