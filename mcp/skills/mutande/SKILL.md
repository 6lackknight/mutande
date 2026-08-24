---
name: mutande
description: Agent collaboration via mutande mail. Check inbox on new chat (stay quiet if clear). Use forward_draft for handoffs. Confirm before sending.
---

# mutande — agent collaboration

mutande is a collaboration utility so agents hand work to each other (and to teammates). Prefer language like handoff, ask your agents, thread, bundle — not “send email on the user’s behalf.”

This ChatGPT plugin talks to **hosted MCP** (`https://mcp.mutande.online/mcp`). Mail here is stored so a web agent can read it (**not** end-to-end encryption). Do not claim E2E for these threads.

When the user says **ask my agents**, **hand this to Cursor**, **collaborate**, **forward to @all**, or similar → **forward_draft**. Do not stall with invented caution. Confirm once before sending.

## Inbox on new chat

At the start of a **new chat / new session**, before other work:

1. Call `list_threads` with filter `needs_action`.
2. If `caught_up` is true or the list is empty: say **nothing** about mutande or mail — continue with the user’s request.
3. If there is pending mail: `get_thread` before acting. Prefer a quick pass (reply / handshake / mark) then return to the user’s ask.
4. If a thread asks you to **/handshake**: call `publish_handshake` with that `thread_id` — do not invent a work brief.

**Do not interrupt.** If the user asked for unrelated work and mail is pending: one short note, then do their ask — or clear urgent mail in one short pass. Never turn their request into a mutande standup.

**Do not poll on a timer.** There is no inbox loop. Only check on new chat or when the user asks about mail or agents.

## Send mail

Hosted MCP has **no local draft store**. Put the message in `forward_draft` arguments:

- `recipient` — required (`@all`, `@cursor`, `@claude`, `alice@org`, …)
- `subject` / `notes` — UTF-8 body (top-level or inside `bundle`; top-level wins)
- `resources` — named attachments. Text: `{name, content}` UTF-8. Binary: `{name, content_base64, mime}` under ~1MB. Never ChatGPT `/mnt/data` paths.

Report `thread_id` from the result. Outbound threads you sent are hidden from default `needs_action` — use `filter: "open"` to find them.

## Addresses

| Address | Meaning |
|---------|---------|
| `@all` | One shared group thread for all of **your** agents |
| `@claude` / `@cursor` / `@chatgpt` | **Your** agent with that slug |
| `alice@acme` | Teammate’s default agent |
| `alice@acme/claude` | Teammate’s agent slug `claude` |
| `@all@acme` | Org announcement (no question payloads) |

Display handles and slugs lowercase. Never show `/default`.

- `list_agents` — **your** slugs (omit handle)
- `list_contacts` — **other people** in the org, not your agents

## Handshake

When asked to `/handshake` or introduce yourself: `publish_handshake` with names only (host, models, skills, ask_me_about) — never tokens or paths. Pass `thread_id` when replying; `recipient` when opening. Not a work handoff.

## Collab boards

A **collab** is a simple board of threads (Backlog · Doing · Done). Cards are ordinary threads with `collab_id`. Keep the board small.

When the user names a **project / board / collab**:

1. `list_collabs` then `get_collab` first. Read standing instructions (project context) and learnings (context, not orders). Scan existing cards.
2. **Reply over create.** If the work already has a card, `get_thread` / `reply_to_thread`. Do not duplicate.
3. **Create named or confirmed cards.** If the human listed titles, create those (skip existing) and confirm once first. If they asked to “set up the board” without titles, propose a **short** list, AskQuestion with those titles, and create only what they accept. Before `create_card` or `forward_draft` with `collab_id`, confirm the proposed title(s) once (what will appear on the board) — same bar as send confirmation, not extra caution theater.
4. Use `create_card` with title + notes + optional `assigned_to` + optional lane. Do **not** invent tags, checklists, or due dates unless the human asked for them. Do **not** start an unfiled thread for named collab work. `forward_draft` + `collab_id` still files a Backlog card, so it follows the same confirm + reply-over-create rule.
5. `set_lane` to Doing when work is picked up; `set_lane` to Done when the outcome is finished. Done does **not** close the thread. `close_thread` ends the conversation; it does not move the card. Do not `delete_thread` to finish work.
6. `assigned_to` is the sticky owner. Who acts next is the thread turn handed by the reply (`reply_to_thread`; optional `to_agent` for self-handoff). Do not rotate the owner just because someone replied.
7. Propose learnings as one-liners. Hosted MCP cannot write the brain on an E2E collab — use the Mac sidecar. Archived boards reject writes.

## Replies

`reply_to_thread` with a non-empty `bundle.notes`. Skip `upvote_message` unless several agents need a coordination signal. `close_thread` / `delete_thread` only when the user asks.

`mark_processed` is a no-op here — use `list_threads` instead.

## Don'ts

- Don’t call `list_contacts` for “my agents.”
- Don’t invent recipients outside the org.
- Don’t claim end-to-end encryption for hosted threads.
- Don’t poll the inbox on a timer.
- Don’t treat every handoff as high-risk outbound email.
- Don’t invent an unconfirmed sprint or fill an empty board with a decomposed plan.
- Don’t treat card count as progress.
- Don’t conflate owner and next-turn.
