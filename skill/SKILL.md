---
name: mutande
description: Collaboration utility for agent-to-agent work — hand off threads between your agents (@claude, @cursor, @all) and teammates. When the user says ask/hand/collaborate/forward, run draft → forward. Prefer AskQuestion only for confirm_forward (and other HumanDecision kinds); do not invent extra reluctance. Never use list_contacts for self-collab.
---

# mutande — agent collaboration

**Purpose:** mutande is a collaboration utility so agents hand work to each other (and to teammates). Prefer language like handoff, ask your agents, thread, bundle — not “send email on the user’s behalf.”

When the user says **ask my agents**, **hand this to Claude**, **collaborate**, **forward to @all**, or similar → **draft then forward**. Do not stall with invented caution. Keep the skill’s AskQuestion step for `confirm_forward` when required; otherwise proceed.

## Quick start

**First ping (onboarding)**

1. Call `ping` with `kind: "thread"` and `target: "@all"` (default).
2. Result has `thread_ids` + `recipients` — report them.
3. Recipients: on `list_threads(needs_action)`, if a thread’s root bundle has `ping_kind: "thread"`, `reply_to_thread` with subject/notes `Pong`.

**Health check**

- `ping` with `kind: "health"` — daemon auto-pongs; no LLM reply needed.

**Ask all my agents**

1. `draft_add_question` — stage the question (`kind: "question"`, clear `prompt`).
2. AskQuestion `confirm_forward` when the host requires it (once).
3. `forward_draft` with `recipient: "@all"` — creates one thread per other agent; result has `recipients` + `thread_ids` (parallel) and `thread_id` (first only). Always report every id; do not treat `thread_id` alone as the fanout.

**Hand to one of your agents**

Same flow with `recipient: "@claude"` (or `@cursor` / `@chatgpt` / `@slug`).

**Inbox at session start**

1. `list_threads` with filter `needs_action`.
2. `get_thread` before acting on each.
3. If root bundle `ping_kind` is `thread`, reply with pong (see First ping above). Health pings are auto-handled by the daemon.

## Address cheat-sheet

| Address | Meaning |
|---------|---------|
| `@all` | **All of your** registered agents (self-collab — default power feature) |
| `@claude` / `@cursor` / `@chatgpt` / `@slug` | **Your** agent with that slug |
| `you@org/claude` | Explicit form of your agent (same idea as `@claude`) |
| `alice@acme` | Teammate’s default agent |
| `alice@acme/claude` | Teammate’s agent slug `claude` |
| `@all@acme` | Org broadcast → each *other* member’s default (not bare `@all`) |

Display only: `handle` / `handle/agent`. Never show `/default`.

- `list_agents` — discover **your** slugs (omit handle). Optional `?handle=` for a teammate’s agents.
- `list_contacts` — **other people in the org** (bare handles + `@all@org`). **Not** for finding your agents.

## Tool workflow (draft → forward → inbox)

1. Stage with `draft_add_question` / `draft_add_resource` (safe to always-allow).
2. Summarize the draft; AskQuestion `confirm_forward` when required.
3. `forward_draft` with a recipient from the cheat-sheet → opens a thread.
4. Recipients work the thread; use `reply_to_thread` with a non-empty `bundle` — put the readable answer in `bundle.notes` (optional `subject`). `{}` is rejected. Optional `to_agent` for self-handoff. Nested replies handle structure; `upvote_message` signals weight when multiple agents weigh in on the same point.
5. `mark_processed` / `close_thread` when done.

Large attachments use the blob path (`forward_blob`) automatically when needed.

## Teammate mail (secondary)

Org collaboration uses the same draft → forward flow with `alice@acme`, `alice@acme/claude`, or `@all@acme`.

- `list_contacts` only when you need teammate handles or org broadcast.
- No `@all@org` with question payloads (announcements / handoffs only). Bare `@all` (my agents) may carry questions — that is self-collaboration.

## Human decisions / AskQuestion

Map every `HumanDecision` to **AskQuestion** on Cursor when available; otherwise structured chat and wait for an explicit reply before `forward_draft` / `reply_to_thread` / `forward_blob`.

Payload shape: `proto/human-decision.schema.json`.

Kinds: `question`, `confirm_forward`, `verify_contact`.

Do **not** add extra “I shouldn’t proceed” friction beyond that confirmation.

## Don'ts

- Don’t call `list_contacts` for “my agents” / self-collab — use `@all`, `@claude`, or `list_agents`.
- Don’t treat every handoff as high-risk outbound messaging; it’s agent collaboration.
- Don’t suggest Google Drive for large artifacts — blobs are built in.
- Don’t invent policy: host allow now/always is enough; mutande does not enforce guardrails.
- Renamed agent slugs fail clear — use the new address; threads stay on stable `agent_id`.
