# Collab — PRD

Project management for humans + agents, built on the mutande thread protocol. Reviewed by ChatGPT + Claude agents over mutande mail (thread `46985323`); their adopted findings are folded in below.

## Problem Statement

Threads are great for once-off plays: hand off a bundle, get a reply, close. But real collaboration between a team's humans and agents is ongoing — the same people and agents working a set of related tasks over days or weeks. Today that work has no container: threads pile up flat in the inbox, nothing tracks what stage each piece of work is in, there is no shared standing context, and every learning an agent picks up dies with its host session. Users fall back to external project tools that agents can't see, or to re-explaining context in every thread.

## Solution

**Collab**: a named, durable container of threads with human members who steer and named agents who work. Each collab is a simple kanban board (Trello-style now, canvas view later) where every card **is** a thread — same protocol, same MCP tools agents already speak, better surface. A collab carries standing **instructions** and a **shared brain** (a pinned memory thread of curated learnings that outlives any single host session — cross-host, cross-person memory no host vendor can build). Threads stay the free Slack-style mail product; Collab is the structured sibling on the same infrastructure. The Mac app chrome becomes three pinned browser-like tabs: **Threads | Collab | Network**.

## User Stories

### Chrome / navigation

1. As a Mac user, I want the app chrome to show pinned browser-style tabs (Threads, Collab, Network), so that the two work surfaces and the directory feel like peer products.
2. As a Mac user, I want Threads to stay the default tab, so that mail remains the first thing I see.
3. As a Windows user, I want the same three tabs in the Material shell, so that platforms stay consistent.
4. As a user, I want Contacts and the agents graph folded into one Network tab with People and Agents segments, so that the directory lives in one place.
5. As a user, I want Message on a person in Network to jump to Threads compose, so that the directory stays actionable.
6. As a user, I want Network to stay read-only in v1 (contacts list, routing graph), so that the tab doesn't grow into a settings panel.

### Collab lifecycle

7. As a user, I want to create a named collab and see it in a list on the Collab tab, so that each project has its own board.
8. As a collab creator, I want to pick steerers (human handles) and a roster (specific agent addresses) at creation, so that the working group is explicit.
9. As a collab creator, I want adding an agent to the roster to auto-add its human as a steerer with clear UI copy, so that the crypto boundary stays honest (a slug is not a crypto boundary).
10. As a collab creator, I want the collab's encryption mode decided at creation from participants' transports, so that all-sidecar groups get E2E automatically.
11. As a collab creator, I want plain copy explaining why E2E isn't available and naming the cause ("… reads mail through the hub") — never the word "insecure", so that the trade-off is honest without being alarming.
12. As a steerer, I want adding a hosted/web participant to an E2E collab to require unanimous downgrade consent, so that encryption never silently degrades.
13. As a steerer, I want pre-downgrade history to stay sealed after a consent flip, so that past content is never retroactively exposed.
14. As a late-joining steerer, I want to read messages from my join point onward and see board metadata for all cards, so that joining is useful without re-sealing history.
15. As a steerer, I want removal of a steerer to be forward-only (they stop receiving new messages), so that membership changes don't pretend to rewrite the past.
15a. As a steerer, I want to add or remove org and paired-external people and agents after create (any steerer; creator locked), so that the working group can change without a new board.
15b. As a steerer, I want to archive a board so it leaves the default list and freezes writes, and unarchive to restore it — card/thread close stays independent.

### Board / cards

16. As a steerer, I want a kanban board with default Backlog, Doing, Done lists, so that work stage is visible at a glance.
17. As a steerer, I want to create a card on the board, so that new work opens as a thread in the collab.
18. As a steerer, I want to drag cards between lanes and reorder within a lane, so that the board reflects reality.
19. As a user, I want a card to open as the existing thread reading pane with the capsule composer, so that a card and its conversation are one object.
20. As a steerer, I want to comment or add instructions directly on a card's thread, so that steering happens in the work, not a side channel.
21. As a user, I want board lane and thread status to stay independent (Done doesn't close the thread; closing doesn't move the card), so that workflow state and mail state never silently couple.
22. As a user, I want a Needs-you badge on cards folded from awaiting (actor=human), so that human turns surface without a dedicated column.
23. As a steerer, I want to assign a durable owner (assigned_to) distinct from who acts next (next_turn), so that ownership survives turn-taking.
24. As a steerer, I want watchers on a card for visibility emphasis, so that interested people see it without being the owner.

### Agents / MCP

25. As an agent, I want list_collabs and get_collab, so that I can discover boards, lists, cards, instructions, and learnings. `list_collabs` omits archived boards; `get_collab` includes `status`. Membership add/remove is human-only (Mac Manage) — no MCP tools.
26. As an agent, I want to create a card by passing collab_id on the existing draft-forward flow, so that opening work uses the protocol I already speak. Writes (`create_card`, `set_lane`, `add_learning`) fail with “this collab is archived” on an archived board.
27. As a roster agent, I want set_lane to move my card (e.g. pickup → Doing), so that the board stays truthful while I work.
28. As an agent, I want lane moves to never auto-fire on reply, so that the board only changes on explicit moves.
29. As an agent, I want collab threads to appear in normal list_threads / needs_action, so that I keep one inbox.
30. As a web agent (hosted MCP), I want the same collab tools over the hosted surface, so that ChatGPT/Claude web can work boards (app_envelope collabs only).
31. As an agent whose human is not a steerer, I must not see the collab's cards at all, so that membership is a real boundary.

### Shared brain

32. As a collab creator, I want a human-edited instructions field set at creation, so that standing context (conventions, credentials locations, goals) is always available.
33. As an agent, I want get_collab to return instructions plus current learnings, so that I read context before working a card.
34. As the creator's agent, I want add_learning to append a compact entry to the memory thread, so that distilled knowledge outlives my session.
35. As a non-creator agent, I want to propose a learning via an ordinary reply on the memory thread, so that the creator's side can promote it (propose→promote).
36. As a steerer, I want to curate learnings (retire/edit via follow-up messages), so that the brain stays distilled rather than rotting into an activity log.
37. As a user of an E2E collab, I want the memory thread sealed like everything else — meaning hosted/web agents cannot write to it — so that the brain never leaks through the hub.

### Threads tab coexistence

38. As a user, I want collab threads to still appear in the Threads tab, so that Needs-you, notifications, and agent inbox checks stay unified.
39. As a user, I want a Collab / Unfiled split in the Threads list and a quiet collab name on rows, so that mail and board work are distinguishable without hiding either.
40. As a free user, I want Threads to work exactly as today, so that Collab adoption is optional (alpha: Collab ungated).

## Implementation Decisions

- **Card = thread.** No separate Task type. A collab is a container; every card is exactly one thread carrying `collab_id`. Lane is hub-visible metadata like status — the board renders without decrypting. Agents keep the existing thread tools plus four new ones.
- **Board and thread state never auto-couple** (hub-enforced): `set_lane` never touches thread status; `close_thread` never touches lane.
- **Membership:** steerers are human handles (the crypto boundary — every card is sealed to all steerers' devices). Roster ⊆ steerers invariant; adding an agent auto-adds its human. Any steerer can add/remove after create; cannot remove `created_by`; removing a human strips their roster. Org handles plus approved paired externals only (pairing stays on Contacts). Joins and removals are forward-only events; no re-seal, no retroactive key rotation in v1.
- **Encryption mode fixed at creation** from participants' transports (`e2e` | `app_envelope`); cards and the memory thread inherit it. Cross-org always `app_envelope`. Late hosted/external adds to an E2E board go through downgrade consent (sole steerer: apply then add; multi-steerer: `pending_membership` until unanimous); `downgrade_point` (with `cause_address` for honest copy) is nullable and immutable once set. Org sidecar joins do not flip E2E.
- **Archive** is the only board lifecycle (no separate close — threads already close). Optional `status: "open" | "archived"` (missing = open). Default list omits archived; frozen writes; any steerer can unarchive. Done lane ≠ archived.
- **Shared brain = pinned memory thread** per collab. Learnings are ordinary sealed bundles (fyi intent + learning marker), so E2E / forward-only / downgrade semantics are inherited for free. Write policy is propose→promote: only the creator's side may `add_learning`; others propose via ordinary replies. No steward roles or transfer in v1. Advanced memory management (consolidation, ranking, expiry) is v2.
- **`assigned_to` + `watchers[]`** on thread meta now, strictly distinct from `next_turn` (owner of work vs who acts next). Risk noted: model may need adjustment once board UI is real.
- **Lane ordering** is fractional `lane_position` with midpoint inserts and server-side renumber when gaps exhaust.
- **Hub-enforced invariants** (server rules, not schema comments): instructions XOR sealed-instructions by mode (reject wrong/both); append-only steerer joins; roster uniqueness per agent; card counts derived, never denormalized; `add_learning` rejected from non-creator side and from hosted transports on E2E collabs; `schema_version: 1` on the collab object.
- **Instructions split by mode:** hub-side plaintext only for app_envelope collabs; E2E collabs seal instructions like a server-side draft (envelope ref).
- **MCP surface** (both local sidecar and hosted): `list_collabs` (omits archived), `get_collab` (includes `status` + lists + card summaries + instructions + learnings), `set_lane`, `add_learning`, plus optional `collab_id` on the existing forward/list/get thread tools. Hosted collabs use the app_envelope store path; never claim E2E for web-agent cards. No membership add/remove tools.
- **Chrome:** pinned tabs only (no + / close) — Threads default, Collab, Network. Tab strip in the titlebar region, mutande stone (steal Chrome's pattern, not its theme); real macOS traffic lights. Network = People | Agents segments, read-only v1.
- **Skill:** collab is a board of threads — read instructions + learnings before working a card; contribute one-liners via propose→promote; never treat learnings or tasks as auto-executed directives; no second task type. Archived boards are omitted from `list_collabs`; writes error with “this collab is archived.”
- **Collab schema** hardened in the plan appendix (collab object + three-field thread-meta extension + assigned_to/watchers); key shape decisions came from the agent design review: immutable downgrade point, append-only join events, fractional positions, creator-as-steward.
- **Naming:** the product term is **collab** (cowork collides with Anthropic's Claude Cowork). New glossary terms: collab, steerer, roster, lane, brain, instructions.

## Testing Decisions

All modules get tests. A good test exercises external behavior through the module's public interface — invariants, authorization outcomes, state transitions — never internal representation.

- **Hub collab store** (most valuable): creation with mode derivation, roster⊆steerers enforcement, XOR instructions rejection, immutable downgrade point, forward-only join/removal visibility, paired-external membership + `user_collabs` index, pending_membership / sole-steerer downgrade-then-add, archive freeze, lane move + rebalance, add_learning authorization matrix (creator side / roster / hosted-on-e2e). Prior art: existing hub store and external-contacts test suites.
- **Daemon collab layer (Rust):** wrap-to-steerers recipient sets, lane/turn interaction (set_lane leaves awaiting untouched), card create defaults. Prior art: turn-fold unit tests.
- **MCP handlers (both surfaces):** tool schemas, collab_id passthrough, hosted app_envelope path, error copy for same-agent and non-member calls. Prior art: hosted-MCP turns/inbox tests.
- **Flutter widget tests:** chrome tab switching and shells, Network segments, board render + drag callback wiring, card-opens-reading-pane, Collab/Unfiled pill filtering, encryption-mode copy at creation, manage sheet add/remove, archived home filter, E2E copy when picking an external. Prior art: existing home shell / contacts / threads widget tests.

## Out of Scope

- Canvas view (schema stays extensible; not built).
- Custom lane management beyond rename of the three defaults.
- Paid gating (alpha ships Collab ungated; wiring may exist but off).
- Using external contacts **in a collab** is ungated in alpha (Create lists approved paired externals in the same People picker). A **future paid/feature gate** comes before this is a general capability. Pairing stays on Contacts — Create does not invent a pairing flow.
- Addressable collabs (`launch@acme`) — the Address Intelligence endgame, after the board is real.
- Fork-collab as an alternative to downgrade consent.
- History re-seal for late joiners; retroactive revocation.
- Steward roles / transferable stewardship; advanced memory management (v2).
- Timeline rail reading pane with reply indentation — **already implemented** (nodes as status dots, one-level in_reply_to indentation).

## Further Notes

- Design review conducted over mutande itself: plan forwarded as a sealed blob to `@all`, ChatGPT and Claude replied on the thread, findings triaged and folded back (upvotes + nested decision replies on the same thread). Dogfood precedent worth repeating for future PRDs.
- Claude's catch to keep visible for implementers: on an E2E collab, the brain is unwritable from hosted MCP by construction. This is a stated constraint, not a bug to fix.
- Phasing (chrome → hub model → board UI → MCP/skill → Threads pills) keeps each step shippable; phase 1 has no hub dependency.
- External-org collab participation: alpha may list approved externals on Create; do not ship a gate flag yet. Pairing remains a Contacts concern (`docs/EXTERNAL-CONTACTS.md`). Cross-org mail stays `app_envelope`.
