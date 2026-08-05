# mutande landing intro — animation review brief

You are a senior motion designer + product explainer director reviewing our marketing hero video. Be concrete and opinionated. Optimize for a silent, looping, square hero next to our landing copy — not a YouTube trailer.

## Product (what must land in ~28s)

**mutande** (always lowercase) is agent-to-agent encrypted mail for teams.

Core idea to prove visually:

1. You already work in AI hosts (Claude Desktop, ChatGPT, Cursor).
2. Agents collaborate in **secure threads** (addresses like `alice@salesco/claude`, short `@chatgpt`).
3. Mail is **E2E encrypted**; the hub is a blind courier.
4. One sealed handoff can fan out to a teammate’s agents (`bob@salesco/openclaw`, etc.).
5. Brand close: MT mark + wordmark `mutande`.

Tagline on the page (do not fight it): **Address Intelligence.**  
Supporting line: Give every intelligence in your organisation a trusted address. Route work by identity, not implementation.

## Where this video lives

- Marketing site hero (`mutande.online`), right column
- Embedded as muted, autoplay, **looping** `<video>` in a rounded square frame
- Format: **1080×1080 @ 60fps**, ~**28s**, then hold on brand
- No audio today (visual-first; Foley later optional)
- Built in **Remotion** (`video/`), cinematic YC-explainer style with per-scene camera push-ins

Because it loops: the ending must reconnect cleanly to the start; avoid a “credits” feeling that dies.

## Visual language (constraints — do not violate)

- Lane: **mythic subtle** — macOS-native quiet courier; light messenger/relay motif
- Palette: stone/relay (`#faf9f7` … `#1c1917`) + bronze accent (`#8b5a2b` / amber `#d4a24c`)
- Mood: calm, trustworthy cofounder infrastructure — **not** chat app, **not** crypto-bro, **not** dark “dev tool”
- Avoid: purple/indigo AI-cliché gradients, glow spam, Web3 kitsch, emoji, dense dashboards, floating badge clutter
- Product name always **`mutande`** lowercase
- Brand mark: MT ligature, white on solid black
- Prefer product UI (host windows, thread UI) over abstract particles as the main idea

## Current storyboard / beat map (locked structure — improve craft within it unless a beat is clearly wrong)

| Beat | Time (approx) | What happens |
|------|----------------|--------------|
| **Compose** | 0–3.5s | Claude Desktop window; user types: `ask @chatgpt to critique this before we send to the team` (draft: `hacktoberfest-plan-wip.md`) |
| **Explainer: threads** | 3.5–5.75s | Full-bleed bold type: “secure collaboration threads for your agents” |
| **Critique / collab** | 5.75–14s | mutande thread UI + orb rail; Claude asks → ChatGPT critiques → seal → upvote; pings between `@claude` and `@chatgpt` |
| **Explainer: E2E** | 14–16.25s | “secure E2E by default” |
| **Transit / fan-out** | 16.25–21.25s | Encrypted capsule shards arc to recipients; Alice side + Bob/Mary/CFO plates; from→to handle chip |
| **Explainer: team** | 21.25–23.5s | “collaborate with your team's agents” |
| **Hold** | 23.5–28s | MT mark + `mutande` wordmark |

Camera: subtle push-ins / breathe on product beats; explainers are flat overlays. Transit pulls to a wide two-column fan-out.

Recipients in fan-out:

- `bob@salesco/openclaw`
- `mary@salesco/kimi`
- `cfo@salesco` (default agent)

## What I want from you

Review the **current video** (and this brief) as if advising a redesign pass. Prioritize clarity of the product story under silent loop conditions.

### 1) First-watch clarity (silent)

- At 0s, 5s, 14s, 21s, 28s: what does a cold visitor understand?
- What is confusing, too fast, or assumes too much?
- Does the story prove “addressable agents + encrypted mail” or does it look like “AI chat with fancy transitions”?

### 2) Pacing & rhythm

- Are explainer cards too long/short vs product demos?
- Does the 8s collaboration beat earn its length?
- Does transit feel like encryption/handoff or generic particle candy?
- Loop seam: hold → restart — any jank or energy drop?

### 3) Motion craft

- Camera: too timid / too floaty / good?
- Springs/easing: sticky UI vs cinematic?
- Hierarchy: where should the eye go each beat?
- Suggest **2–3 intentional hero motions** max (not a motion salad).

### 4) Type & copy

Critique the three explainer lines for hero density and claim accuracy:

1. secure collaboration threads for your agents
2. secure E2E by default
3. collaborate with your team's agents

Propose stronger alternatives (short, bold, scannable at 68px-ish). Avoid hype words we can’t back. Never say “we store nothing.”

### 5) Composition in the landing frame

Hero is square, often ~smaller than full viewport, beside brand + CTA. Call out:

- Too much chrome / tiny type at display size
- Safe margins, contrast on stone background
- Whether host-window chrome helps or clutters

### 6) Concrete revision plan

Give a prioritized punch list:

- **Keep**
- **Change now** (high leverage)
- **Optional later**

For each change: *what / why / how* (Remotion-friendly: timing frames, opacity, camera scale, copy, layout — not vague “make it pop”).

### 7) Optional: alternate 20s cut

If 28s is too long for a looping hero, propose a tighter 20s beat map that still lands the three ideas: threads → E2E → team fan-out.

## Output format

1. **Verdict** (2–4 sentences)
2. **Clarity score** 1–10 + why
3. **Top 5 issues** (ranked)
4. **Revised beat map** (table with times)
5. **Copy options** for the 3 explainers (A/B)
6. **Motion notes** (specific ease/camera/transition suggestions)
7. **Do-not-do list** for this brand

If I attach the MP4/poster, ground every critique in what you actually see. If I don’t attach media, work from this brief and flag assumptions.

## Attach when pasting into ChatGPT

- `web/public/brand/landing-intro.mp4`
- `web/public/brand/landing-intro-poster.png` (optional)
