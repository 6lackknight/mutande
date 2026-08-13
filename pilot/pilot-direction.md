# Pilot direction — three strategies

Living doc. Revisit after **each pilot session** and whenever **waitlist** or **in-app feedback** moves meaningfully. Pick **one primary wedge** for the next 4–8 weeks; the others stay explicit so we don’t drift.

**Inputs**

| Source | Where | What to read |
|--------|--------|--------------|
| Pilot calls | `pilot/sessions/*.md` | Self-collab + ping pass/fail; **keep app open?**; blockers ≥2 people; would-use why |
| Waitlist | `/admin/ops` → Waitlist | `ai_hosts`, `oses`, `share_frequency`, `share_methods` |
| In-app feedback | `/admin/ops` → Feedback | Freeform quotes, categories, version |
| Ops rule | `pilot/README.md` | Fix blockers that hit **≥2** pilot friends before polish or promotion |

**Current snapshot (2026-08-13)**

- Pilot: **1/5** — Roy (2026-08-12): both pings pass; **keep app open = yes**; setup friction (MCP, notifications, Keychain); strong “tab loop / copy-paste” + enterprise curiosity
- Waitlist: **9 entries** (Aug 4–8, 2026) — see breakdown below
- Gate before public LinkedIn push: finish 5 pilots + ≥2-people blocker sprint (Roy already flagged MCP/onboarding)

### Waitlist stats (from `/admin/ops`, 2026-08-13)

| Metric | n=9 | n=8 excl. founder (`t@tawandabrandon.co`) |
|--------|-----|-------------------------------------------|
| **Share frequency** | 6× multiple/day · 1× few/week · 1× occasionally · 1× rarely/never | 5× multiple/day · 1× each other bucket |
| **OS** | 6 macOS · 3 Windows | 5 macOS · 3 Windows |
| **Multi-host (≥2 AI tools)** | 6 (67%) | 5 (63%) |
| **Copy / paste** | 8 (89%) | 7 (88%) |
| **Cloud (Drive/Dropbox)** | 5 (56%) | 5 (63%) |
| **Local files / notes** | 4 (44%) | 4 (50%) |
| **Email** | 2 | 2 |
| **Slack / chat** | 0 | 0 |
| **Company domain email** | 5 | 4 |

**Top hosts (mentions across entries):** Claude Desktop 6 · Claude Code 4 · ChatGPT desktop 4 · Gemini 4 · Cursor 2 · GitHub Copilot 1 · ChatGPT web 1

**Notable rows:** Roy (`roy@berrydeep.com`) — Cursor-only, occasionally, copy/paste — matches pilot session. Lebo — heaviest multi-host (5 tools). Three Windows signups — alpha not ready for them yet.

**Strategy score (waitlist only):**

| Strategy | Signal strength | Why |
|----------|-----------------|-----|
| **A — Cofounder** | **High** | 67% multi-host; 67% share multiple/day; copy/paste universal pain |
| **B — Enterprise** | **Low** | Some `.co` / `.com` domains; no compliance-led answers on this form |
| **C — Developer / MCP** | **High** | Claude Code, Cursor, Copilot; multi-tool power users |

**Lead wedge (today):** **A + C** — cofounder/copy-paste story in public; dev credibility in docs and hosted-MCP setup. Batch invites: **macOS + ≥2 hosts + multiple/day** first (5–6 people). Hold Windows until published.

---

## Strategy A — Cofounder wedge (default if waitlist looks like us)

**Thesis:** mutande wins as **agent mail for people building together** — replace WhatsApp/email copy-paste between cofounders’ agents. Personal `@all` + one teammate thread is the day-one success path.

**Signals to chase this**

- Waitlist: **“Multiple times a day”** or **“A few times a week”** share frequency; methods include **Copy/paste**, **Slack/chat**, **Email**
- Pilot: **keep app open = yes/maybe**; would-use cites **tab switching**, **handoffs**, **async** not **compliance**
- Hosts: **Cursor + Claude + ChatGPT** mix (matches v1)

**Product priorities**

1. Boring install path: DMG → Auth0 → connect host → self-collab ping → teammate ping (pilot flow)
2. Onboarding: MCP + skill in **two clear steps**; notification + Keychain copy that explains *why*
3. Threads UI for “did my cofounder’s agent reply?” — not spatial graph yet
4. Defer: enterprise registry polish, Windows, billing

**Launch**

- **Private alpha** until 5/5 pilots + blocker sprint
- Then: **Try Alpha** on site + invite waitlist in **small batches** (10–20), not open flood
- Success metric: **2nd session without you on the call** (they ping each other unprompted)

**Marketing & social**

- **LinkedIn** (primary): founder POV — “we were copy-pasting between Cursor and Claude”; 60–90s screen capture of personal `@all` ping → reply in Threads
- **X**: same clips; reply in builder threads about multi-agent workflows
- **Avoid:** “platform for everything”; lead with **one painful loop** (tabs → one address)
- Content cadence: 1 demo video / 2 weeks while alpha; changelog tied to pilot blockers fixed

**YC / a16z path**

- **YC:** Strong fit — narrow problem, technical founder, early “email for agents” metaphor, retention question from pilot template
- **a16z:** Weaker until team/org revenue; mention only as long-term TAM
- Traction story: 5 pilot **yes** on keep-open + waitlist conversion to installed org + week-2 active threads
- Application narrative: *Hermes layer for agent handoffs*; show Roy-style demo (self-collab + live thread), not roadmap slides

**Risks:** Stays small if we only solve “two founders”; hard to differentiate from “just use Slack.” **Kill or pivot if:** ≥3 pilots say **no** on keep-open, or waitlist is mostly single-host / rare sharing.

---

## Strategy B — Enterprise & regulated (sales-led)

**Thesis:** mutande is **E2E agent courier inside the org boundary** — local models, proprietary code, audit-friendly metadata. Buyers care about *who can message which agent*, not viral growth.

**Signals to chase this**

- Pilot: delight on **Keychain / safety number / encrypted blobs**; asks for **local model**, **university**, **org-wide agent** (`@org/agent`)
- Waitlist: emails from **company domains**; OS skew enterprise; share methods **Drive + Slack** at scale
- Roy session (n=1): enterprise/local-model framing **clicked**; Stripe + US entity already aligned

**Product priorities**

1. Enterprise registry + trust tier story (already in hub) — **one** design partner, not self-serve
2. Admin narrative: invite-only org, blind hub, ciphertext-only storage
3. On-prem / local-model agent address as **documented** path (even if v1 is “bring your MCP”)
4. Pilot-specific: reduce MCP ceremony for **IT-approved** connector install

**Launch**

- **No broad LinkedIn** until one **named design partner** (university dept, agency, or corp eng team) runs 30-day pilot
- Landing: secondary **“Talk to us”** / enterprise waitlist slice — not hero CTA
- Legal/trust: short security page (what hub sees vs doesn’t); cost transparency doc for buyers (Roy asked for this)

**Marketing & social**

- **Minimal social virality** — credibility over clips
- **LinkedIn:** occasional long-form on **E2E agent routing** (not product hype); tag design partner only with permission
- **Conferences / private briefings** > HN front page
- Case study format: *before* (paste in Slack) → *after* (encrypted thread + PR handoff) with metrics

**YC / a16z path**

- **YC:** Possible if framed as **infra for agent adoption inside companies** — need 1–2 LOIs or paid pilot, not just interest
- **a16z:** Better fit if we lead with **security + agent orchestration** and show enterprise registry + billing ledger
- Fundraise story: design-partner pipeline, per-message/per-seat unit economics, **no** “we store nothing” overclaim
- Timeline: 6–12 months to first paid org; don’t optimize site for consumers

**Risks:** Long cycles, feature pull from one buyer, Mac-only limits IT. **Kill or pivot if:** zero design-partner meetings after 10 targeted outbound, or pilots only want free cofounder tool.

---

## Strategy C — Developer / MCP mesh (community-led)

**Thesis:** mutande is the **address + thread layer for MCP-native agents** — protocol people, skill broadcast, repo/PR handoff, hosted MCP at `mcp.mutande.online`. Growth through builders who already live in Cursor/Claude connectors.

**Signals to chase this**

- Pilot: delight on **MCP connect**, **PR/file forward**, **agent loops**, **skill install**; frustration is *docs*, not *concept*
- Waitlist: **Cursor + Claude Code + Windsurf + GitHub Copilot**; share methods **local files / notes**, **Drive**
- In-app feedback: MCP/OAuth/connector errors

**Product priorities**

1. **Hosted MCP** setup ≤3 steps (ChatGPT/Claude web path in `docs/HOSTED-MCP.md`)
2. Skill hub + catalog discoverability; “install skill” in connect flow bulletproof
3. Public docs: addressing, `@all`, `forward_blob`, thread semantics — Show HN-ready
4. Windows alpha when hub path works (waitlist **Windows** count is trigger)

**Launch**

- **Show HN** + **MCP ecosystem posts** after blocker sprint (MCP onboarding must not need a live call)
- Open alpha for waitlist **dev segment** first (filter: ≥2 AI hosts + macOS)
- Roy’s landing-page workflow test = good **dogfood template** for dev content

**Marketing & social**

- **X / dev LinkedIn:** architecture threads — blind courier, wrap-to-N, thread IDs; open-core crypto angle
- **Short demos:** agent loop, PR between agents, hosted MCP in ChatGPT — technical captions, not lifestyle
- **Discord/slack communities:** Cursor, MCP, indie hackers — answer “how is this not email” with live thread link
- SEO/docs: “agent-to-agent MCP”, “handoff between Claude and Cursor”

**YC / a16z path**

- **YC:** “Plumbing for the agent internet” — show GitHub stars, waitlist dev density, connector installs
- **a16z:** AI infra bucket if we show **hosted MCP** adoption and ISV/skills marketplace path (mutande-ai catalog)
- Metrics: hosted MCP OAuth completes, skill installs, threads/agent/week on free tier

**Risks:** Crowded MCP narrative; perceived as devtool not business. **Kill or pivot if:** pilots succeed only when you’re on the call for MCP, or waitlist is non-technical with no multi-host pain.

---

## How to choose (after 5 pilots + waitlist review)

Score each strategy 0–3 on:

1. **Keep-open rate** (pilots) — yes=3, maybe=1, no=0  
2. **Waitlist fit** — % matching strategy’s host/OS/frequency profile  
3. **Blocker overlap** — do fixes for one strategy unblock the others?  
4. **Fundraising story** — which narrative matches where we’ll apply in next 90 days?  
5. **Founder energy** — which wedge do we want to sell repeatedly?

| If highest score is… | Primary motion next 8 weeks |
|----------------------|-----------------------------|
| **A — Cofounder** | Finish pilots → LinkedIn batch → batch waitlist invites → YC draft |
| **B — Enterprise** | 10 targeted outbound → 1 design partner → security page → defer viral |
| **C — Developer** | MCP onboarding sprint → Show HN → docs push → Windows when ready |

**Blends (allowed, pick one lead):**

- **A + C** (likely today): cofounder story publicly, dev credibility in docs/HN — *same product, different front door*
- **B + C:** enterprise security story with MCP as integration surface — sales deck + technical eval doc
- **Avoid A + B** without segment-specific landing: confuses “Get started” vs “Contact sales”

---

## Shared checklist (any strategy)

- [ ] Complete **5/5** pilot sessions (`pilot/TEMPLATE.md`)
- [ ] Run **≥2-people blocker** sprint
- [x] Export waitlist summary into **Current snapshot** above (2026-08-13, n=9)
- [ ] Roy: landing-page workflow test → capture as short clip or quote
- [ ] Decide: LinkedIn now vs after batch 2 (Roy/Tawanda agreed: small group before public promotion)
- [ ] Update `web/src/lib/changelog.ts` when alpha cut fixes pilot blockers — social proof

---

## Open questions (update as data arrives)

1. ~~Waitlist: macOS vs Windows?~~ **67% macOS / 33% Windows** (n=9) — Windows wait; macOS batch first  
2. ~~Waitlist: share frequency?~~ **67% multiple/day** — strong A signal  
3. Pilots 2–5: does **enterprise** come up unprompted? (→ B) — Roy n=1 yes on call, not on waitlist form  
4. Can MCP connect succeed **without** a live call? (gate for C and any public launch)  
5. First paid intent: individual team vs org contract?
