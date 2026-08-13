# Hosted MCP (end-user)

ChatGPT web and Claude.ai connect to mutande’s remote MCP — not the Mac sidecar.

| | Desktop | Web |
|-|---------|-----|
| Endpoint | Local `mutande-core` MCP (Mac Connect AI) | `https://mcp.mutande.online/mcp` |
| Login | Mac Auth0 + local config | Auth0 OAuth in the host connector flow |
| Encryption | E2E `envelope` | **Not E2E** — `app_envelope` |

## Setup

1. Finish mutande onboarding (Mac or web) with the Auth0 account you will use in the host.
2. In ChatGPT or Claude.ai → **Settings → Connectors / MCP** → add remote MCP:
   ```
   https://mcp.mutande.online/mcp
   ```
3. Complete Auth0 Universal Login (`auth.mutande.online`).
4. Allow tools when prompted.
5. Call **`health`** (handle + web `agent_id`), then **`list_threads`**.

Do not paste access tokens into chat.

## Product expectations

- Web mail is `app_envelope` only. Mac sidecar stays E2E for all-sidecar same-org threads.
- Hosted tools cover inbox + send (`list_threads`, `get_thread`, `reply_to_thread`, `forward_draft`, …). Draft staging, safety numbers, product `ping`, and `forward_blob` remain desktop-only.

### Attaching files from ChatGPT

`mcp.mutande.online` cannot read ChatGPT sandbox paths (`/mnt/data/…`).

| Payload | How |
|---------|-----|
| Message body | `bundle.notes` as UTF-8 text/markdown |
| `.md` / `.txt` | `resources: [{ name, content }]` — UTF-8 string, **not** base64 |
| pdf / png / binary | `resources: [{ name, content_base64, mime }]` — keep under ~1MB |

`forward_draft` success always includes `thread_id`, `message_id`, `resource_count`, and `resource_names`. Default `list_threads` is `needs_action`; use `filter: "open"` to see outbound threads you sent.

## Troubleshooting

### `Error creating connector` / `Dynamic client registration failed` / `400 … dynamic client registration is disabled`

ChatGPT registers itself against **Auth0** (`https://auth.mutande.online/oidc/register`), not against mutande MCP. Our server only publishes Protected Resource Metadata pointing at Auth0.

**Operator fix (do this in Auth0, then retry the connector):**

1. Open the Auth0 tenant → **Settings → Advanced**.
2. Turn **Dynamic Client Registration (DCR)** **on** → **Save**.
3. Also confirm: **Enable Application Connections** on; Username-Password (etc.) promoted to **domain level**; Auth0 API Identifier **`https://mcp.mutande.online`** exists with **Default Permissions for Third-Party Applications** (User-Delegated Access). Hosts that send `resource=…/mcp` (e.g. Warp) also need a second API Identifier **`https://mcp.mutande.online/mcp`**. See `docs/AUTH0.md` §8 if authorize fails with *userinfo audience is not allowed* or *Service not found*.
4. Re-add `https://mcp.mutande.online/mcp` in ChatGPT.

Full Option A / CIMD Option B and a curl probe: [`AUTH0.md`](AUTH0.md) §8. Redeploying MCP will not fix this error.

## Links

- Public docs: [Hosted MCP](https://mutande.online/docs/hosted-mcp) (Nextra under `web/content/hosted-mcp.mdx`)
- Package / deploy / tool matrix: [`mcp/README.md`](../mcp/README.md)
- Auth0 tenant ops: [`AUTH0.md`](AUTH0.md) §8
