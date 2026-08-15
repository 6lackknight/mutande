# mutande — Google Stitch scope (macOS app)

Design scope for **Stitch** mocks of the mutande macOS menu-bar app. Web (`mutande.online`) is out of scope except as the brand/logo source.

---

## Goal

Produce a coherent, high-fidelity screen set for the Mac tray app so Flutter can follow Stitch instead of ad-hoc Material. Prioritize **end-to-end product flows** over decorative chrome.

**Out of scope for this pass:** iOS companion, web redesign, marketing site beyond logo pull, hub admin.

---

## Brand assets (use these)

**Masters** live in repo `brand/sources/` (`ai-mark.png` = `@i` seal, `ai-glyph.png` / `ai-glyph-white.png` = transparent mark, `mt-ligature.png`). Regenerate consumers with `./scripts/sync-brand-assets.sh` (see `brand/README.md`). Hosted on prod web — prefer these URLs in Stitch:

| Asset | URL | Use |
|-------|-----|-----|
| `@i` mark (white on black) | https://mutande.online/brand/mt-mark.png | Primary seal — splash, About-style moments, large brand. Filename is historical (`mt-mark`); art is **`@i`**, not MT letters. |
| MT ligature (legacy) | https://mutande.online/brand/mt-ligature.png | Optional secondary mark where the wordmark ligature still fits |
| Tray / favicon glyph (no plate) | https://mutande.online/brand/tray-icon.png | Menu-bar glyph, in-app nav mark, small brand (`@i` on transparent) |
| Favicon / touch | https://mutande.online/brand/favicon-32.png · [icon-192](https://mutande.online/brand/icon-192.png) · [apple-touch](https://mutande.online/brand/apple-touch-icon.png) | Favicon is the transparent glyph; apple-touch / 192 stay plated |

**Wordmark:** always lowercase **`mutande`** (never “Mutande”). SF Pro / system UI sans. Slightly tight tracking, semibold for titles.

**Mark rules:** Brand mark is **`@i`** (Address Intelligence). Prefer **white mark on solid black** for seals / AppIcon. Tray and favicon use the transparent glyph. Do not invent a second logo, orb-as-logo, envelope mascot, or gradient lock.

---

## Product one-liner

Agent-to-agent encrypted mail for teams. Quiet courier. Hub is blind; plaintext stays on-device.

Domain terms: **thread**, **bundle**, **handoff**, **collab**, **org**, **handle** (`alice@acme`), **agent handle** (`alice@acme/claude`), **my-agents** (bare `@all`), **broadcast** (`@all@acme`), **self shorthand** (`@claude`).

### Addressing hierarchy (must be visible in UI)

Mail routes through a **human handle**, then into **agent slots** under that handle:

```
alice@acme                    ← human handle (bare address)
└── default                   ← default agent (receives bare + @all@org fan-in)
    │                          display: alice@acme  (never alice@acme/default)
    ├── claude                ← alice@acme/claude   (also addressable as @claude when you)
    ├── cursor                ← alice@acme/cursor
    ├── chatgpt               ← alice@acme/chatgpt
    └── [ + Add ]             ← empty node — only way to add a sub-agent
```

Rules for Stitch copy and trees:

| Rule | Detail |
|------|--------|
| Bare handle | `alice@acme` always means the **default** agent |
| Reserved slug | `/default` is **not** a user-facing address — never show `alice@acme/default` |
| Label in tree | Show the default row as **default** (or “Default agent”) under the handle, with a clear badge |
| Sub-agents | Routed **under default**, not as siblings of default at the handle level |
| **Add sub-agent** | **Only** via an **empty node** connected to **default**, with an **Add** control — not a floating FAB, not a top-toolbar “New agent”, not from Session |
| Empty node | Always visible under default when more agents can be added; looks like a placeholder/ghost slot, not a full agent row |
| Other agents | Children of default: slug + full display `alice@acme/<slug>` |
| Set default | User can promote another agent to default; tree updates so that row wears the default badge |
| Self shorthand | When addressing yourself: `@claude` / `@cursor` / `@slug` (not a contact-list row) |
| My agents | Bare `@all` fans out to **all of your** agents — caption near tree / composer if shown |
| Broadcast | `@all@acme` fans out to each *other* member’s **default** agent only; sole-member orgs seal to own devices |
| Connected now | Session may highlight which agent/host is currently connected (MCP) vs merely registered |

Wire path (for designers, not primary UI): `acme/alice/claude`. Prefer display form in the app.

---

## Platform constraints (hard)

Design inside these — Stitch frames should match:

| Constraint | Spec |
|------------|------|
| Shell | macOS **menu-bar accessory** (no Dock icon) |
| Window | **1088 × 720** pt default (**816 × 540** min), titled `mutande` (tray utility — not a full IDE) |
| Close | Hides window; app stays via tray |
| Tray | Solid black plate + white MT; not a template silhouette |
| Theme | System light/dark eventually; **v1 mocks: light stone first**, then one dark pass for splash + tray |
| Motion | Minimal — badge/status updates only; orbs for loading/welcome |
| Trust | Verify UI serious (Signal / 1Password), not playful |

---

## Antipatterns (avoid these)

Obvious desktop / tray mistakes. If a mock looks like any of these, redesign.

### Wrong product shape

| Antipattern | Why it fails here |
|-------------|-------------------|
| Full-width SaaS dashboard / sidebar app | This is a **1088×720 menu-bar utility**, not Linear/Notion |
| Dock-first “big app” chrome (sidebar + toolbar + inspector) | No Dock icon; window is secondary to the tray |
| Mobile patterns (bottom tab bars, huge touch targets, sheet stacks) | Design for mouse/trackpad density and macOS HIG |
| Marketing landing squeezed into a window | No hero stats, logo walls, or “Book a demo” energy in-app |
| Chat product UI (bubbles, typing dots, emoji reactions) | Mail/handoff, not messenger cosplay |

### Layout & density

| Antipattern | Prefer instead |
|-------------|----------------|
| Cards wrapping every row | Flat lists, hairline separators, quiet grouping |
| Nested scroll regions fighting each other | One primary scroll per pane |
| Modals for routine actions | Inline, sheets only when necessary |
| Wallpaper / full-bleed photography in chrome | Stone wash, spare atmosphere; brand seal is enough |
| Padding that wastes half the window height | Compact; status at a glance — use the extra room for list density, not empty hero space |
| Tiny hit targets *and* sparse empty voids | Comfortable controls without sparse “web page” spacing |

### macOS / tray specifics

| Antipattern | Prefer instead |
|-------------|----------------|
| Custom window chrome that fights traffic lights | Standard macOS title bar |
| Colored / glowing tray icon, animated tray glyph | Static `@i` plate; status lives in the menu text |
| Assuming close = quit | Close **hides**; Quit only from tray |
| System Settings dump as the home screen | Home = Threads · Collab · Network; Settings holds plumbing |
| Windows-style ribbon / oversized toolbar | Minimal AppBar + tabs |
| Ignoring vibrancy / light-dark later | Design light first; don’t lock to pure white web cards |

### Motion & feedback

| Antipattern | Prefer instead |
|-------------|----------------|
| Constant Lottie / skeleton theater | Searching/working **orbs** only when waiting |
| Confetti, toast spam, success fireworks | Quiet confirmations; verify is serious |
| Spinners that reset onboarding on failure | Keep last-known state; Retry, don’t bounce to Join |
| Fake “AI thinking” purple glow / particle soup | Monochrome orbs; bronze accent only |

### Brand & content

| Antipattern | Prefer instead |
|-------------|----------------|
| “Mutande” title case / ALL CAPS wordmark | lowercase **mutande** |
| Second logo, robot mascot, Hermes/wings/lightning | MT mark + wordmark only |
| Web3 / crypto wallet aesthetic | Quiet courier / infrastructure |
| Showing `alice@acme/default` | Bare handle + **Default** badge |
| Dev chrome (DEBUG banner, hub URL, raw JWTs, localhost) | Everyday-user UI only |
| Playful verify / gamified trust | Signal-grade seriousness |

### Information architecture

| Antipattern | Prefer instead |
|-------------|----------------|
| Four+ equal tabs (Verify/Session as peers of Threads) | **Threads · Collab · Network**; rest in **Settings** |
| Agents buried only under Settings | Agents stays a **main tab** (routing is core) |
| Flat list of hosts with no default concept | Handle → default → sub-agents |
| “New agent” in toolbar / FAB / Settings-only create | **Add** on the **empty node** under default |
| Empty node as a full fake agent row | Ghost/placeholder slot with clear Add |
| Org chart / mind-map for three agents | Compact indented tree |
| Exposing wire paths `acme/alice/claude` as primary labels | Display addresses `alice@acme/claude` |

**Smell test:** If the frame would look at home in a B2B web app after removing the traffic lights, it’s wrong.

---

## Visual system

**Lane:** mythic subtle — macOS-native quiet courier, faint messenger/relay motif (not literal Hermes).

| Token | Value |
|-------|--------|
| Surface | `#FAFAF9` |
| Background | `#F5F5F4` |
| Border | `#E7E5E4` |
| Ink | `#292524` / `#44403C` / `#57534E` |
| Muted | `#78716C` / `#A8A29E` |
| Bronze accent / focus | `#92400E` |
| Button fill | `#57534E` → light fg |
| Emerald (open / ok) | `#166534` (+ soft `#ECFDF5`) |
| Amber (pending / needs you) | `#B45309` (+ soft `#FDE68A`) |
| Red (error / no match) | `#991B1B` |
| Splash black | `#0C0A09` |

**Loading language (already shipped in Flutter):**

- **searching** orb — idle / list / standard wait  
- **working** orb — button actions, connect, welcome splash  
- Sizes: ~20 inline, ~64 panel  

Do not replace orbs with Material spinners in mocks.

---

## Screen inventory (design these)

### A. System chrome

1. **Menu bar** — tray icon among other status items; tooltip `mutande`.  
2. **Tray menu** — `Daemon: up|down|…` (disabled status) · Open mutande · Connect AI hosts · Quit.  
3. **Window chrome** — traffic lights + title `mutande` at **1088×720** (816×540 min).

### B. Launch & routing

4. **Welcome splash** — full window `#0C0A09`, centered **working** orb (light ink), ~3s. No wordmark required; optional tiny MT if it stays quiet.  
5. **Bootstrap loading** — stone bg, centered **searching** orb.  
6. **Daemon unreachable** — brand mark + title + short help + **Retry**. Never look like Join/sign-in.

### C. Onboarding (Auth0, same account as web)

7. **Sign in** — MT + `mutande`, “Sign in”, one line about Auth0/browser, primary **Sign in with Auth0**. No hub URL field.  
8. **Choose path** — email shown; **Create a team** / **I have an invite**.  
9. **Create team** — team slug (required), team name (optional), handle (optional); Create / Back.  
10. **Join with invite** — invite code, handle (optional); Join / Back.  

Handle hints: `alice` or `alice@acme`. Slug: lowercase letters, numbers, hyphens.

### D. Home shell (minimal nav)

**Law:** Main window is for **mail + routing**. Plumbing and trust live under **Settings** (gear in AppBar or tray → Settings) — not equal tabs.

Shared chrome: AppBar `mutande` + handle (or “Agent-to-agent mail”) + Settings affordance. Optional quiet cue **default · claude**. Soft **Retry status** banner if daemon blipped.

**Tab bar — three pinned tabs (no + / close):**

| Tab | Role | Required |
|-----|------|----------|
| **Threads** | Inbox / handoffs | Yes |
| **Collab** | Boards of threads (Backlog / Doing / Done) | Yes |
| **Network** | People (contacts) · Agents (routing graph). Read-only in v1. | Yes |

Do **not** put Verify, Session/Connect, or Contacts as peer home tabs. Contacts and Agents fold into **Network**.

**Settings** (pushed screen or sheet — not a tab):

| Section | Contents |
|---------|----------|
| Daemon | Status, Check daemon, Retry |
| AI hosts | Connect Cursor / Claude / ChatGPT (MCP + skill) + results |
| Notifications | Master switch, mail for agents, Needs you, per-agent toggles |
| Verify | Safety numbers (serious trust UI) |
| Account | Email, sign out (if applicable) |
| About | MT mark + lowercase mutande |

Tray may still expose **Connect AI hosts** as a shortcut; destination UI lives in Settings → AI hosts, then cue back to **Agents** for the tree.

### E. Threads

11. **List** — filters: Needs you · Open · Closed. Rows: peer/audience (prefer display agent handle when not default), `kind · status · your_status`, status color (amber pending, emerald open, muted closed). Mute/Unmute from context menu. Refresh.  
12. **Empty** — `No threads.` calm, not illustrated mascot.  
13. **Detail** — message list (plaintext or “(no plaintext)”), reply field “Short note for their agent”, send. Closed threads: reply disabled. Show from/to as `alice@acme` or `alice@acme/claude` per addressing rules. Mute in overflow.  
14. **List/detail loading & error** — panel orb; red inline errors.

### F. Network — Agents (routing)

**List UI with indent, not a node canvas.** Three levels: handle → default → (sub-agents + empty Add). No org-chart connectors. Lives under **Network → Agents**.

15. **Agents list (populated)** — indented rows; default badge; host chips; Connected / Idle; trailing **ghost row** under default with **Add**.  
16. **Add sub-agent** — only via that empty node under default (pick/bind host, slug). Empty node stays for next add. No FAB / AppBar New.  
17. **Set as default** — on a sub-agent; badge moves; Add node stays under the current default.  
18. **Agent detail (optional)** — slug, display address, host, default yes/no. Never show `…/default`.  
19. **No agents yet** — CTA into Settings → AI hosts; after connect, land on Agents with default + empty Add. Copy: “Connect an AI host for your default agent, then Add under default for more.”  
20. **Loading / error** — panel orb; inline errors.

### G. Network — People (contacts)

Address book lives under **Network → People**, not a peer home tab.

21. **Contacts list** — org members as `bob@acme` (and agent suffix only if useful); synthetic **`@all@acme`** row with caption that fan-out hits each *other* member’s **default** agent (not bare `@all` / `@slug`).  
22. **Empty / loading** — “No teammates yet” + invite cue (web) if needed; panel orb.  
23. **Row action (light)** — start thread / copy handle — keep sparse; no CRM profile pages.

### H. Settings (everything else)

Pushed from gear — stack of sections, not a second tab bar.

24. **Settings hub** — list: Daemon · AI hosts · Verify · Account · About.  
25. **Daemon** — Connected/Disconnected/Unknown; Check daemon; Retry.  
26. **AI hosts** — Connect Cursor / Claude / ChatGPT; Connected / Failed; ChatGPT MCP hint; after success: “View agents” → Agents tab.  
27. **Verify** — safety number, lookup, compare; Match / No match (serious).  
28. **About** — MT mark + `mutande`.

---

## States checklist (every primary screen)

For each screen above, Stitch should cover when relevant:

- Default / populated  
- Loading (orb)  
- Empty  
- Error (inline, not full panic unless daemon-unreachable)  
- Success confirmation (verify match; connect hosts)

---

## Sample content (use consistently)

```
handle:           alice@acme
default agent:    claude     → receives alice@acme  (label: default — not /default)
other agents:     cursor     → alice@acme/cursor  (self: @cursor)
                  chatgpt    → alice@acme/chatgpt
peer:             bob@acme
peer agent:       bob@acme/cursor   (when not their default)
org slug:         acme
my-agents:        @all       → all of alice’s agents
broadcast:        @all@acme  → each *other* member’s default only
invite:           (paste-looking token, not a real secret)
thread:           open · pending · “Needs you”
safety:           grouped digit blocks like Signal
daemon:           Connected / up
```

---

## Priority order for Stitch

1. Splash → Sign in → Choose → Create / Join  
2. **Home chrome** (Threads · Collab · Network + Settings gear) + Threads list / empty / detail  
3. **Collab** board (lists + cards + empty Create)  
4. **Network** (People = contacts + `@all@org`; Agents = routing graph)  
5. Settings hub + AI hosts + Verify (match / no match) + Daemon  
6. Daemon unreachable + tray menu + menu-bar crop  
7. Dark splash refinement  

---

## Acceptance criteria

- Looks like a **compact macOS tray utility**, not a SaaS marketing page or chat app.  
- Main nav is **minimal**: Threads · Collab · Network; Verify / Connect / Daemon under **Settings**.  
- Brand: lowercase wordmark + MT assets from Vercel URLs above.  
- Status colors convey open / pending / closed at a glance.  
- **Agents** is an indented list (not a node graph): handle → **default** → sub-agents; add only via **Add** on the empty node under default; never display `…/default` as an address.  
- Verify feels grave and clear (in Settings).  
- No hub URL, DEBUG ribbon, or developer env chrome in user flows.  
- Frames sized for **1280×720** (and a menu-bar strip for tray).

---

## Handoff

Deliver Stitch frames (or export) named by screen id, e.g. `mac-04-splash`, `mac-11-threads-list`. Flutter implementation will map 1:1 into `app/lib/screens/` and `app/lib/widgets/`.

Reference product context: `CONTEXT.md` (visual language), `docs/PRD.md` (flows). Live brand: [mutande.online](https://mutande.online).
