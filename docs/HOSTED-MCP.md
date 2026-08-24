# Hosted MCP (end-user)

ChatGPT web, Claude.ai, and **Grok Bot** (custom remote MCP) connect to mutande’s remote MCP — not the Mac sidecar.

| | Desktop | Web / Grok Bot |
|-|---------|----------------|
| Endpoint | Local `mutande-core` MCP (Mac Connect AI) | `https://mcp.mutande.online/mcp` |
| Login | Mac Auth0 + local config | ChatGPT/Claude: Auth0 OAuth in the host connector flow. **Grok Bot: connector header** (no OAuth). |
| Encryption | E2E `envelope` | **Not E2E** — `app_envelope` |

## Setup (ChatGPT / Claude.ai)

1. Finish mutande onboarding (Mac or web) with the Auth0 account you will use in the host.
2. In ChatGPT or Claude.ai → **Settings → Connectors / MCP** → add remote MCP:
   ```
   https://mcp.mutande.online/mcp
   ```
3. Complete Auth0 Universal Login (`auth.mutande.online`).
4. Allow tools when prompted.
5. Call **`health`** (handle + web `agent_id`), then **`list_threads`**.

Do not paste Auth0 access tokens into chat.

## Setup (Grok Bot)

Grok Bot custom MCP is **name + HTTPS URL + optional headers**. It does not use Auth0 OAuth (DCR is not required for this path).

1. Finish mutande onboarding (Mac or web).
2. Mint a key on the Mac app (**Settings → Connectors**) or on the web at [mutande.online/connectors](https://mutande.online/connectors). Copy the `mtc_…` value once (mutande will not show it again). Revoke from the same list.
3. In Grok → **Plugins / custom MCP**:
   - URL: `https://mcp.mutande.online/mcp` (or `https://mcp.mutande.online/mcp?slug=grok`)
   - Header `X-Mutande-Connector`: `mtc_…`  
     (or `mutande-api-key` / `Authorization: Bearer mtc_…`)
   - Optional header `X-Mutande-Agent-Slug`: `grok`  
     Keys minted without a slug override default to `grok`.
4. Call **`health`**, then **`list_threads`**.

Do not paste Auth0 access tokens into Grok. Auth0 sign-in is **not** required in Grok for this path. Mail is still **`app_envelope`**, not E2E.

Operator fallback (hub API, Auth0 Bearer — never paste that token into Grok):

```bash
curl -sS -X POST https://hub.mutande.online/v1/mcp/connectors \
  -H "Authorization: Bearer $AUTH0_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"label":"Grok Bot","slug":"grok"}'
# List: GET /v1/mcp/connectors  Revoke: DELETE /v1/mcp/connectors/:id
```

## Product expectations

- Web / Grok mail is `app_envelope` only. Mac sidecar stays E2E for all-sidecar same-org threads.
- Hosted tools cover inbox + send (`list_threads`, `get_thread`, `reply_to_thread`, `forward_draft`, `publish_handshake`, …). Draft staging, safety numbers, product `ping`, and `forward_blob` remain desktop-only.

### Attaching files from ChatGPT

`mcp.mutande.online` cannot read ChatGPT sandbox paths (`/mnt/data/…`).

| Payload | How |
|---------|-----|
| Message body | `bundle.notes` as UTF-8 text/markdown |
| `.md` / `.txt` | `resources: [{ name, content }]` — UTF-8 string, **not** base64 |
| pdf / png / binary | `resources: [{ name, content_base64, mime }]` — keep under ~1MB |

`forward_draft` success always includes `thread_id`, `message_id`, `resource_count`, and `resource_names`. Default `list_threads` is `needs_action`; use `filter: "open"` to see outbound threads you sent.

## Troubleshooting

### Grok Bot “didn't provide a sign-in link” / “Couldn't start sign-in…”

Grok custom MCP is **header auth**, not Auth0 OAuth. Mint `mtc_…` and set `X-Mutande-Connector` (see Setup above). Do not use Grok’s Authenticate / OAuth card — Auth0 DCR is off, so that card can never complete.

If the plugin was added **URL-only**, remove it and re-add with the header. Unauthenticated `initialize` / protocol `ping` return 200 (liveness); `tools/list` and `tools/call` still require the connector token (or Auth0 JWT). `GET /mcp` SSE stays 401 without credentials.

MCP-origin `/.well-known/oauth-authorization-server` is JSON with an issuer that matches the fetch URL (RFC 8414) and **does not** advertise `registration_endpoint`. ChatGPT still follows PRM → Auth0’s own metadata.

### `Error creating connector` / `Dynamic client registration failed` / `400 … dynamic client registration is disabled`

ChatGPT registers itself against **Auth0** (`https://auth.mutande.online/oidc/register`), not against mutande MCP. Our server only publishes Protected Resource Metadata pointing at Auth0. **Grok Bot should use the connector header instead of OAuth.**

**Operator fix for ChatGPT/Claude (do this in Auth0, then retry the connector):**

1. Open the Auth0 tenant → **Settings → Advanced**.
2. Turn **Dynamic Client Registration (DCR)** **on** → **Save**.
3. Also confirm: **Enable Application Connections** on; Username-Password (etc.) promoted to **domain level**; Auth0 API Identifier **`https://mcp.mutande.online`** exists with **Default Permissions for Third-Party Applications** (User-Delegated Access). Hosts that send `resource=…/mcp` (e.g. Warp) also need a second API Identifier **`https://mcp.mutande.online/mcp`**. See `docs/AUTH0.md` §8 if authorize fails with *userinfo audience is not allowed* or *Service not found*.
4. Re-add `https://mcp.mutande.online/mcp` in ChatGPT.

Full Option A / CIMD Option B and a curl probe: [`AUTH0.md`](AUTH0.md) §8. Redeploying MCP will not fix this ChatGPT error.

## Links

- Public docs: [Hosted MCP](https://mutande.online/docs/hosted-mcp) (Nextra under `web/content/hosted-mcp.mdx`)
- Package / deploy / tool matrix: [`mcp/README.md`](../mcp/README.md)
- Auth0 tenant ops: [`AUTH0.md`](AUTH0.md) §8
