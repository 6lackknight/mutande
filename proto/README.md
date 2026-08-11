# Proto

JSON schemas shared across hub, core, and agent skill.

- `bundle.schema.json` — plaintext payload before E2E encryption
- `human-decision.schema.json` — AskQuestion / chat fallback shape
- `thread-meta.schema.json` — hub-visible thread headers
- `inbox-events.schema.json` — local daemon WebSocket frames (`inbox_changed`, subscribe)
- `agent-capabilities.schema.json` — client-declared capability bundle on connect (L1)
- `agent.schema.json` — hub agent slot record after assignment (dual transport rows)
