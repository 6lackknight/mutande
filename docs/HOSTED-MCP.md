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

## Links

- Public docs: [Hosted MCP](https://mutande.online/docs/hosted-mcp) (Nextra under `web/content/hosted-mcp.mdx`)
- Package / deploy / tool matrix: [`mcp/README.md`](../mcp/README.md)
- Auth0 tenant ops: [`AUTH0.md`](AUTH0.md) §8
