# TODO: Update /docs for self-collaboration addressing

Handoff for a documentation agent. Self-collaboration addressing shipped locally; user-facing docs need to catch up. **Do not rewrite this brief — inventory and patch the real docs.**

Source of truth for product language: `CONTEXT.md` (glossary + agent router). Prefer that over older UI/scope notes when they disagree.

## Why

Addressing now covers same-user agent collaboration (`@claude` / bare `@all`) plus org broadcast (`@all@org`), stable `agent_id` + renameable slug, and hub agent registry. `/docs` (and related surfaces) still describe the older handle-only / default-agent story in places.

## Address model to document

| Address | Meaning |
|---------|---------|
| `@claude`, `@cursor`, `@chatgpt`, custom `@slug` | Current user's agent with that slug |
| `@all` | All of **my** agents (not org members) |
| `@all@org` | Org broadcast → each *other* member's **default** agent |
| `you@org/claude` / `alice@acme/claude` | Explicit agent-scoped |
| `alice@acme` | Default agent (never show `/default`) |
| Wire form | `acme/alice/claude` (internal) |
| Display | `alice@acme/claude` |

## Related product facts (cover where relevant)

- [ ] Stable `agent_id` (UUID) vs renameable slug; threads key on `agent_id`; renamed slugs fail with a clear “use the new address” hint
- [ ] Agents auto-register on MCP host connect
- [ ] Default agent + router (`default_agent_id` + `rules[]`); bare handle → default; document v1 default-agent-only / router behavior per `CONTEXT.md`
- [ ] Same-user subagent collaboration (Cursor ↔ Claude ↔ ChatGPT) via `@slug`, `you@org/slug`, or bare self when connected agent ≠ default / reply `to_agent`
- [ ] Sole-member `@all@org` encrypts to own devices (default-agent inbox)
- [ ] `list_contacts` stays bare handles; shorthand `@slug` is for self only
- [ ] Flutter routing graph: Add can pick idle hosts; Agent Inspector polish (mention if docs cover Mac UI)
- [ ] Hub `GET/POST /v1/agents` (etc.) must be **deployed** for prod — call out in hub/ops docs

## Checklist for the docs agent

1. [ ] Inventory `docs/` for every user-facing addressing mention (`handle`, `@all`, agent slug, broadcast, wire vs display).
2. [ ] Align copy with the table above and `CONTEXT.md` (especially **my-agents** vs **broadcast**, sole-member edge case).
3. [ ] Update related non-`docs/` surfaces if they still teach old addressing:
   - `CONTEXT.md` — verify glossary/router stay canonical (fix only if drift)
   - `skill/SKILL.md` — agent-facing addressing examples; framing = collaboration utility (not scary messaging API)
   - `hub/README.md` — agent registry / `/v1/agents` deploy note
4. [ ] Flag or fix stale hierarchy in `docs/STITCH-MAC-SCOPE.md` / `docs/PRD.md` / `docs/architecture.md` / `docs/UPDATES.md` if they omit `@all` (my agents) or self shorthand.
5. [ ] Keep tone everyday-user friendly in product docs; reserve wire paths for architecture/hub notes.

## Likely targets

| Path | Why |
|------|-----|
| `docs/PRD.md` | Stories still say handle / `@all` without my-agents vs org split |
| `docs/architecture.md` | Routing, wire form, hub agents API |
| `docs/UPDATES.md` | Changelog / “what changed” if used |
| `docs/STITCH-MAC-SCOPE.md` | UI addressing hierarchy; may predate bare `@all` / `@slug` |
| `docs/AUTH0.md` | Only if it mentions handles/routing (probably skip) |
| `CONTEXT.md` | Canonical glossary — sync if needed |
| `skill/SKILL.md` | MCP agent instructions |
| `hub/README.md` | Deploy `/v1/agents` for prod |

## Done when

A reader of `/docs` + skill can correctly address `@claude`, `@all`, `@all@org`, bare handles, and `handle/agent`, and knows wire vs display, without contradicting `CONTEXT.md`.
