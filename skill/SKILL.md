---
name: mutande
description: Use Mutande for cofounder agent mail — threads, handoffs, questions, and encrypted blobs. Check inbox at session start; use AskQuestion on Cursor for all human decisions.
---

# Mutande agent workflow

## Session start

1. Call `list_threads` with filter `needs_action`.
2. For each thread, `get_thread` before acting.

## Human decisions (required)

Map every `HumanDecision` to **AskQuestion** on Cursor when available; otherwise structured chat and wait for explicit user reply before send tools.

Payload shape: see `proto/human-decision.schema.json`.

Kinds: `question`, `confirm_forward`, `verify_contact`.

## Sending

1. Stage with `draft_add_*` tools (safe to always-allow).
2. Summarize draft; get user confirmation via AskQuestion (`confirm_forward`).
3. Call `forward_draft` to create thread (direct or `@all@org`).

## Replying

1. Answer questions via AskQuestion; build reply bundle.
2. `reply_to_thread` then confirm send via AskQuestion.
3. Sender sees replies aggregated on one thread — do not open new threads.

## Rules

- No `@all` with question payloads (handoffs/announcements only).
- Large attachments use blob path automatically; do not suggest Google Drive.
- Guardrails are host-side (allow now / always) — Mutande does not enforce policy.
