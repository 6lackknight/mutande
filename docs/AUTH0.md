# Auth0 setup (Mutande)

Free-tier Auth0 tenant for hub (API tokens), Vercel web (Regular Web App), macOS (Native App), and hosted MCP. Hub Identifier `https://hub.mutande.app` for Mac/web; ChatGPT MCP also needs API Identifier `https://mcp.mutande.online` (§8).

Canonical hub audience in this repo: `https://hub.mutande.app` (Auth0 API Identifier). Mac, web, and hub share that value; hosted MCP accepts it plus the MCP resource audience.

## 1. API (hub)

Dashboard → **Applications → APIs → Create API**

| Field | Value |
|-------|--------|
| Name | Mutande Hub |
| Identifier | `https://hub.mutande.app` |
| Signing | RS256 (default) |

This Identifier is `AUTH0_AUDIENCE` everywhere.

## 2. Regular Web Application (Vercel / local Next.js)

Dashboard → **Applications → Create Application → Regular Web Application**

**Prod web (until `mutande.ai`):** `https://mutande.online`  
Optional aliases: `https://mutande.vercel.app`, `https://mutande-web.vercel.app`

**Allowed Callback URLs**

```
http://localhost:3000/auth/callback
https://mutande.online/auth/callback
https://mutande.vercel.app/auth/callback
https://mutande-web.vercel.app/auth/callback
https://*.vercel.app/auth/callback
```

(Auth0 accepts the Vercel subdomain wildcard for previews; keep the exact prod callback above as primary.)

**Allowed Logout URLs**

```
http://localhost:3000
https://mutande.online
https://mutande.online/auth/logout
https://mutande.vercel.app
https://mutande.vercel.app/auth/logout
https://mutande-web.vercel.app
https://mutande-web.vercel.app/auth/logout
https://*.vercel.app
```

**Allowed Web Origins**

```
http://localhost:3000
https://mutande.online
https://mutande.vercel.app
https://mutande-web.vercel.app
https://*.vercel.app
```

Grant this app access to the Mutande Hub API (APIs → Mutande Hub → Machine to Machine / Application access, or Applications → APIs tab). Web uses `@auth0/nextjs-auth0` routes: `/auth/login`, `/auth/logout`, `/auth/callback`, `/auth/access-token`.

## 3. Native Application (macOS)

Dashboard → **Applications → Create Application → Native**

Daemon prefers loopback port **8732** (`http://127.0.0.1:8732/callback`). If that port is busy it falls back to an ephemeral port and logs the exact redirect URI.

**Allowed Callback URLs**

```
http://127.0.0.1:8732/callback
http://127.0.0.1:3848/auth/callback
```

(`3848` is the local pilot ops dashboard — see `pilot/ops`.)

**Allowed Logout URLs / Web Origins** (ops)

```
http://127.0.0.1:3848
```

No client secret. Grant types: Authorization Code, Refresh Token. Enable Offline Access. Request `audience=https://hub.mutande.app` so access tokens validate on the hub.

Env: `AUTH0_DOMAIN`, `AUTH0_NATIVE_CLIENT_ID`, `AUTH0_AUDIENCE` (see `core/.env.example`). Flutter can pass the same via `--dart-define`. Optional plumbing: `MUTANDE_AUTH0_ACCESS_TOKEN` skips the browser.

## 4. Database connection (dashboard — not via Auth0 MCP)

Auth0 MCP in this workspace has no connection/passwordless tools. Do this in the dashboard:

1. **Authentication → Database** → open `Username-Password-Authentication` (or create a DB connection).
2. Enable **Username / Password** (and Disable Sign Ups only if you want invite-only).
3. **Authentication → Passwordless** → enable **Email** (magic link and/or code) if you want that Universal Login option.
4. **Applications → Mutande Web → Connections** and **Mutande Mac → Connections**: enable the DB (and Passwordless Email) connections on both apps.

Custom login domain: `auth.mutande.online` (set as `AUTH0_DOMAIN` everywhere — JWKS + authorize).  
Manage tenant: [chevrondigital](https://manage.auth0.com/dashboard/us/chevrondigital/).

## 5. Environment variables

### Hub (Deno Deploy + local `hub/.env`)

| Variable | Notes |
|----------|--------|
| `AUTH0_DOMAIN` | Auth0 host / custom domain, e.g. `auth.mutande.online` (no `https://`) |
| `AUTH0_AUDIENCE` | API Identifier, e.g. `https://hub.mutande.app` |

Plus R2 vars from `hub/.env.example` for real blobs.

Deploy: set vars in Deno Deploy → project **mutande** → Settings → Environment Variables, then:

```bash
cd hub && deno task deploy
```

Hub hard-requires `AUTH0_DOMAIN` + `AUTH0_AUDIENCE` when `DENO_DEPLOYMENT_ID` is set. Do not invent secrets.

### Web (Vercel + local `web/.env.local`)

| Variable | Notes |
|----------|--------|
| `AUTH0_DOMAIN` | Custom domain `auth.mutande.online` (not tenant `*.auth0.com`) |
| `AUTH0_CLIENT_ID` | Regular Web Application |
| `AUTH0_CLIENT_SECRET` | Regular Web Application |
| `AUTH0_SECRET` | `openssl rand -hex 32` (session cookie) |
| `AUTH0_AUDIENCE` | Same as hub |
| `APP_BASE_URL` | Local: `http://localhost:3000`. Production: `https://mutande.online` (until `mutande.ai`) |
| `MUTANDE_HUB_URL` | e.g. `https://hub.mutande.online` |
| `PLUNK_API_KEY` | Optional invite email |

### Mac (daemon env or Flutter `--dart-define`)

| Variable | Notes |
|----------|--------|
| `AUTH0_DOMAIN` | Custom domain `auth.mutande.online` (not tenant `*.auth0.com`) |
| `AUTH0_NATIVE_CLIENT_ID` | Native Application (no secret) |
| `AUTH0_AUDIENCE` | Same as hub |
| `MUTANDE_HUB_URL` | e.g. `https://hub.mutande.online` |
| `MUTANDE_AUTH0_ACCESS_TOKEN` | Optional — skip OAuth browser |
| `MUTANDE_AUTH0_REFRESH_TOKEN` | Optional with access token |

Persisted in `~/.mutande/config.json` (`0o600`): `access_token`, `refresh_token`, `hub_url`, Auth0 fields.

## 6. Token contract

1. Client obtains an Auth0 **access token** with the hub audience.
2. Call hub with `Authorization: Bearer <access_token>`.
3. Hub verifies via JWKS (`AUTH0_DOMAIN` issuer + `AUTH0_AUDIENCE`).
4. Onboarding: `GET /v1/me` → create org or join invite → `POST /v1/devices`.

Legacy hub JWT is gone; do not restore it.

## 7. Product-owner ops (SuperAdmin)

`/admin/ops` and hub `GET /v1/admin/feedback` + `GET /v1/admin/waitlist` require Auth0 role **SuperAdmin** (`rol_jsa0BZq7uzz2K4RG`), not hub `org_admin`.

1. **User Management → Roles** — create `SuperAdmin` (already present).
2. Assign that role to product-owner users.
3. **Actions → Login / Post Login** — add roles onto the **access token** (Auth0 does not put role names in the token by default):

```js
/**
 * mutande — Post Login: role claims for ops gates.
 *
 * Must stay harmless for third-party / DCR clients (ChatGPT + Claude.ai hosted
 * MCP, client_id `tpc_…`): claims only, never deny, never touch an access token
 * that is not a JWT for one of our APIs.
 */
exports.onExecutePostLogin = async (event, api) => {
  const HUB_AUDIENCE = "https://hub.mutande.app";
  const MCP_AUDIENCE = "https://mcp.mutande.online";
  const CLAIM = `${HUB_AUDIENCE}/roles`;

  const roles = event.authorization?.roles ?? [];
  if (!roles.length) return; // no roles is normal — never deny login here

  // Audience actually resolved for this transaction. `event.resource_server` is
  // absent when no API audience was requested (opaque /userinfo access token).
  const audience =
    event.resource_server?.identifier ??
    event.request?.query?.audience ??
    event.request?.query?.resource ??
    "";
  const isOurApi = audience === HUB_AUDIENCE || audience === MCP_AUDIENCE;
  const isThirdParty = String(event.client?.client_id ?? "").startsWith("tpc_");

  try {
    // Hub/web gate reads the access token; MCP-aud tokens are forwarded to hub,
    // so both audiences carry the same claim.
    if (isOurApi) api.accessToken.setCustomClaim(CLAIM, roles);
    // ID token → session.user for web nav. First-party only.
    if (!isThirdParty) api.idToken.setCustomClaim(CLAIM, roles);
  } catch (_) {
    // A claim failure must never break sign-in for MCP connector flows.
  }
};
```

Enable **RBAC** on the Auth0 API (`https://hub.mutande.app`) so `event.authorization.roles` is populated. Hub/web also accept `https://mutande.app/roles`, `https://mutande.online/roles`, and bare `roles`. Override allowed role names/ids with hub env `MUTANDE_PLATFORM_ADMIN_ROLES` (comma-separated; default `SuperAdmin,rol_jsa0BZq7uzz2K4RG`).

**This Action must not break hosted MCP.** Rules for any future edit:

- Never call `api.access.deny(...)` on missing roles/orgs — DCR clients (`tpc_…`) hit the same Post Login flow and would fail the connector OAuth.
- Guard `api.accessToken.setCustomClaim` on a real API audience. Post Login cannot change or clear the audience, but writing access-token claims when the token is the opaque `…/userinfo` one is pointless and can surface as an Action error.
- Keep `https://mcp.mutande.online` in the allowed-audience list so ChatGPT tokens (aud = MCP) still carry roles when hub sees the forwarded Bearer.
- Actions run **after** audience resolution. `resource` → audience mapping is a tenant setting plus a matching API Identifier — not something an Action can fix. See [`userinfo audience is not allowed`](#troubleshooting-the-userinfo-audience-is-not-allowed-for-third-party-clients).

After assigning the role or changing the Action, users must **sign out and sign in** so a fresh access token includes the claim. Org invites stay gated by hub `org_admin`.

## 8. Hosted MCP (ChatGPT web / Claude.ai) — L0

**Prod status:** live at `https://mcp.mutande.online` (`mcp/` package). This section is the operator checklist for Auth0 OAuth so ChatGPT / Claude.ai can register as MCP clients.

Web hosts connect **to us**; identity is the same Auth0 account as Mac/hub. No platform JWTs in v1.

**End users adding a connector:** [`docs/HOSTED-MCP.md`](HOSTED-MCP.md) (URL + OAuth + tool expectations). Package/redeploy: [`mcp/README.md`](../mcp/README.md).

### How OAuth discovery works (DCR is Auth0, not MCP)

Hosted MCP is the **resource server**. It does **not** implement Dynamic Client Registration.

1. Client hits `https://mcp.mutande.online/mcp` → `401` + `WWW-Authenticate` with `resource_metadata`.
2. Client fetches RFC 9728 PRM at `https://mcp.mutande.online/.well-known/oauth-protected-resource` → `authorization_servers: ["https://auth.mutande.online/"]`.
3. Client fetches Auth0 AS metadata → `registration_endpoint: https://auth.mutande.online/oidc/register`.
4. ChatGPT (and similar hosts) **POST** that Auth0 endpoint to create a third-party app (DCR).

If Auth0 DCR is off, registration returns **400** `dynamic client registration is disabled` and ChatGPT shows *Error creating connector / Dynamic client registration failed*.

Custom domain `auth.mutande.online` uses the same tenant flags as [chevrondigital](https://manage.auth0.com/dashboard/us/chevrondigital/) — enable DCR once on the tenant; both hostnames share it.

### Tenant toggles (MCP clients)

Dashboard → **Settings → Advanced** (tenant settings; same for custom domain):

1. **Resource Parameter Compatibility Profile** — on  
2. **Include Issuer in Authorization Responses** — on  
3. **Dynamic Client Registration (DCR)** — on (required for ChatGPT’s default connector flow; see troubleshooting below)  
4. **Enable Application Connections** — on (so newly registered third-party apps can use domain connections)  
5. Optional (Auth0-recommended longer term): **Client ID Metadata Document Registration** — on, then import ChatGPT/Claude CIMD URLs instead of open DCR

Verify 1 and the MCP API from the outside with `./scripts/auth0-mcp-doctor.sh` (no secrets; hits PRM + `/authorize` probes).

Promote Username-Password (and any social / passwordless connections MCP clients should use) to **domain-level** so third-party apps can authenticate (`is_domain_connection: true`). DCR clients (`tpc_…`) **cannot** use per-app connection toggles — only domain-level connections.

**Dashboard (required for ChatGPT after DCR):**

1. **Authentication → Database** → open `Username-Password-Authentication` (or your DB connection).
2. **Settings** tab → scroll to **Advanced** → enable **Promote Connection to Domain Level** → **Save Changes**.
3. Repeat for any other login method users need (e.g. **Authentication → Passwordless → Email** → Settings → same promote toggle; Social connections the same way).
4. Confirm tenant flag: [Settings → Advanced](https://manage.auth0.com/dashboard/us/chevrondigital/tenant/advanced) → **Enable Application Connections** = **on** → **Save**.

Do **not** try to fix this by opening **Applications → ChatGPT (`tpc_…`) → Connections** and flipping toggles — third-party apps only inherit domain-level connections; the UI often still shows them “disabled.”

**Management API alternative** (scope `update:connections`):

```bash
# List connections → find id, then:
curl --request PATCH \
  --url 'https://chevrondigital.us.auth0.com/api/v2/connections/CONNECTION_ID' \
  --header 'authorization: Bearer MGMT_API_ACCESS_TOKEN' \
  --header 'content-type: application/json' \
  --data '{ "is_domain_connection": true }'
```

(Use the tenant Management API host, not the custom login domain.)

### Audience (ChatGPT requires MCP API)

MCP PRM advertises `resource: https://mcp.mutande.online` (RFC 9728). ChatGPT DCR sends that as `resource=` and **does not** add `audience=https://hub.mutande.app`. With **Resource Parameter Compatibility** on, Auth0 maps `resource` → access-token `aud`. That identifier **must** exist as an Auth0 API, or Auth0 falls back to `…/userinfo` and third-party clients fail (see troubleshooting below).

Do **not** change PRM to advertise the hub Identifier — ChatGPT will not request hub aud when the protected resource is MCP.

**Create API (required for ChatGPT):**

1. **Applications → APIs → Create API**
2. **Identifier** exactly `https://mcp.mutande.online` (must match `MCP_PUBLIC_URL` / PRM `resource`)
3. Signing Algorithm RS256 → **Create**
4. **Settings → Default Permissions for Third-Party Applications** → **User-Delegated Access** = **Authorized** → **Save**

Keep the existing Hub API `https://hub.mutande.app` for Mac / web first-party apps (unchanged).

**Same Bearer, dual audience (L0, no OBO):** ChatGPT tokens have `aud=https://mcp.mutande.online`. MCP and hub both accept that audience **and** the hub Identifier:

| Deploy | Env |
|--------|-----|
| `mutande-mcp` | `AUTH0_AUDIENCE=https://hub.mutande.app` · `AUTH0_MCP_AUDIENCE=https://mcp.mutande.online` |
| `mutande` (hub) | `AUTH0_AUDIENCE=https://hub.mutande.app` · `AUTH0_MCP_AUDIENCE=https://mcp.mutande.online` |

Still grant third-party defaults on **Hub** API too if you ever issue hub-aud tokens from first-party hosts. Optional later: OBO / token exchange MCP → hub only (Auth0 “call your APIs on a user’s behalf”) instead of dual-aud.

Before enabling DCR, confirm third-party defaults on **both** APIs or DCR clients authenticate but cannot get a usable access token.

### Client registration

#### Option A — Enable DCR (fastest fix for ChatGPT)

1. [Tenant Advanced](https://manage.auth0.com/dashboard/us/chevrondigital/tenant/advanced): turn **Dynamic Client Registration (DCR)** **on** → **Save**.
2. Confirm MCP API `https://mcp.mutande.online` exists + third-party defaults (Audience section above); hub API defaults as needed.
3. Confirm domain-level connections + **Enable Application Connections**.
4. Probe (expect **201**, not 400):

```bash
curl -sS -o /tmp/dcr.json -w '%{http_code}\n' -X POST \
  https://auth.mutande.online/oidc/register \
  -H 'content-type: application/json' \
  -d '{
    "client_name": "mutande-dcr-probe",
    "redirect_uris": ["https://chatgpt.com/connector_platform_oauth_redirect"],
    "token_endpoint_auth_method": "none",
    "grant_types": ["authorization_code", "refresh_token"],
    "response_types": ["code"]
  }'
```

5. Re-add the connector in ChatGPT: `https://mcp.mutande.online/mcp`.

Auth0 open DCR lets anyone POST `/oidc/register`. Fine for alpha; for production prefer CIMD (Option B) or Enterprise Tenant ACL / reverse-proxy controls. Delete leftover `mutande-dcr-probe` apps under **Applications** after probing.

#### Option B — Manual / CIMD (no open DCR)

ChatGPT’s connector UI does **not** reliably accept a pasted Auth0 `client_id` for remote MCP. Prefer Auth0 **CIMD import** (or keep DCR on):

1. **Settings → Advanced** → enable **Client ID Metadata Document Registration**.
2. **Applications → Create Application → Import from URL** — paste the CIMD URL ChatGPT/Claude shows for the connector (often `https://chatgpt.com/oauth/.../client.json`), preview, create.
3. Grant that third-party app access to API `https://mcp.mutande.online` (and hub if needed — per-app **Application Access**, or default third-party permissions).
4. Ensure domain-level connections.

If you instead create a normal **Native / SPA** app by hand: Authorization Code + PKCE, Refresh Token, Offline Access, no secret, callbacks such as `https://chatgpt.com/connector_platform_oauth_redirect` and any `https://chatgpt.com/connector/oauth/{callback_id}` ChatGPT displays — then only hosts that prompt for a pre-registered `client_id` can use it. ChatGPT’s default path still expects DCR or CIMD.

### Troubleshooting: `Dynamic client registration failed` / `registration endpoint returned 400`

Exact Auth0 body: `Bad Request: dynamic client registration is disabled`.

| Check | Where |
|-------|--------|
| DCR toggle off | **Settings → Advanced → Dynamic Client Registration (DCR)** |
| Probe still 400 | `POST https://auth.mutande.online/oidc/register` (see Option A) |
| Login fails after DCR works | See **no connections enabled** below |
| Token works but hub 401/403 | API **Default Permissions for Third-Party Applications** on `https://hub.mutande.app` |
| Wrong host | MCP PRM must list `https://auth.mutande.online/` — not a registration URL on `mcp.mutande.online` |

This is an **Auth0 tenant** issue, not a Deno Deploy / MCP code bug. Do not redeploy MCP to “fix” DCR.

### Troubleshooting: `no connections enabled for the client`

**Symptom:** DCR succeeded (ChatGPT appears under Applications with `client_id` like `tpc_…`). Authorize then fails. Auth0 log example:

```
description: "no connections enabled for the client"
client_id: "tpc_…"
client_name: "ChatGPT"
resource: "https://mcp.mutande.online"
```

**Cause:** DCR apps are **third-party**. They may only authenticate via **domain-level** connections. If nothing is promoted, Universal Login has zero connections for that client.

**Fix (chevrondigital / `auth.mutande.online`):**

1. [Tenant Advanced](https://manage.auth0.com/dashboard/us/chevrondigital/tenant/advanced): **Enable Application Connections** = **on** → **Save**.
2. **Authentication → Database** → `Username-Password-Authentication` → **Settings** → **Advanced** → **Promote Connection to Domain Level** = **on** → **Save Changes**.
3. Promote Passwordless Email / Social the same way if those methods should appear on MCP login.
4. Re-try the ChatGPT connector OAuth (same `tpc_…` client is fine; no need to re-DCR). Optionally delete stale ChatGPT third-party apps under **Applications** and re-add the connector if the host cached a bad authorize URL.

**Not this error:** `resource=https://mcp.mutande.online` in the Auth0 log is expected (RFC 8707 from MCP PRM). If authorize still falls through to `audience=…/userinfo`, see **userinfo audience is not allowed** below — that is a missing MCP API Identifier, not a connections issue.

### Troubleshooting: `The userinfo audience is not allowed for third party clients`

**Symptom:** Past “no connections”. Authorize fails. Auth0 log example:

```
description: "The userinfo audience is not allowed for third party clients. Please specify a valid API audience."
client_id: "tpc_…"
resource: "https://mcp.mutande.online"
audience: "https://chevrondigital.auth0.com/userinfo"
scope: "openid email offline_access profile"
```

No `audience=https://hub.mutande.app` in the query string (ChatGPT only sends `resource`).

**Cause:** Auth0 did not turn `resource` into an audience, so it fell back to the userinfo audience — blocked for third-party / DCR clients. Two independent things must both be true; either one missing produces this exact error:

1. **Resource Parameter Compatibility Profile** is on — a **tenant** setting under **Settings → Advanced**, *not* a per-API setting. Off by default, and easy to miss because the error mentions an API.
2. An Auth0 API exists whose Identifier is **exactly** `https://mcp.mutande.online` (no trailing slash — `…online/` is a different string and Auth0 answers `Service not found`).

Run `./scripts/auth0-mcp-doctor.sh` to tell the two apart without dashboard access or secrets; it probes `/authorize` with a bogus `resource`, which only fails when the compatibility profile is on.

**Fix (chevrondigital):**

1. [Tenant Advanced](https://manage.auth0.com/dashboard/us/chevrondigital/tenant/advanced) → **Resource Parameter Compatibility Profile** = **on** → **Save**.
2. **Applications → APIs → Create API** — Identifier **`https://mcp.mutande.online`** (exact match to PRM `resource` / `MCP_PUBLIC_URL`).
3. On that API → **Default Permissions for Third-Party Applications** → **User-Delegated Access** = **Authorized** → **Save**. Also leave **Allow Offline Access** on — ChatGPT requests `offline_access`.
4. Deploy env (both projects) and redeploy:
   - MCP (`mutande-mcp`): `AUTH0_MCP_AUDIENCE=https://mcp.mutande.online` (keep `AUTH0_AUDIENCE=https://hub.mutande.app`)
   - Hub (`mutande`): same `AUTH0_MCP_AUDIENCE=https://mcp.mutande.online`
5. Re-try ChatGPT connector OAuth (same `tpc_…` is fine).

**Do not** rewrite PRM `resource` to the hub Identifier hoping ChatGPT will request hub aud — it won’t. OBO is optional later; dual-aud is the L0 path.

**Not the cause:** `actions.executions` in the failed log entry. Auth0 Actions run after audience resolution and have no API for changing it (`api.accessToken.setCustomClaim` only adds claims), so a Post-Login Action cannot clear or redirect the audience. The executions array appears on normal logins too.

**Not the roles Action.** The Post Login roles Action ([§7](#7-product-owner-ops-superadmin)) cannot cause or fix this: Auth0 resolves the audience and rejects third-party userinfo audiences *before* Actions run, and Post Login has no API to set, change, or clear the audience. The failed log entry shows no Action execution. Verify by temporarily disabling the Action — the same error persists. Still keep the Action third-party-safe (no `api.access.deny`, access-token claims guarded on audience) so it does not add a *second* failure once the MCP API exists.

### Env (Deno Deploy project `mutande-mcp`)

| Variable | Notes |
|----------|--------|
| `AUTH0_DOMAIN` | `auth.mutande.online` |
| `AUTH0_AUDIENCE` | `https://hub.mutande.app` |
| `AUTH0_MCP_AUDIENCE` | `https://mcp.mutande.online` (required for ChatGPT tokens) |
| `MCP_PUBLIC_URL` | `https://mcp.mutande.online` |
| `MUTANDE_HUB_URL` | `https://hub.mutande.online` |
| `MCP_DEFAULT_AGENT_SLUG` | default `chatgpt` |

Hub Deploy project `mutande` must set the same **`AUTH0_MCP_AUDIENCE=https://mcp.mutande.online`** so MCP-forwarded Bearers validate. Hub must also keep **`APP_ENVELOPE_KEY`** set in prod for app_envelope mail at rest — not an MCP env var.

Redeploy MCP: `cd mcp && deno task deploy`.

## See also

- [`docs/HOSTED-MCP.md`](HOSTED-MCP.md) — ChatGPT / Claude connector (end user)
- `hub/README.md` — API routes + deploy
- `mcp/README.md` — hosted MCP package, tools, redeploy
- `web/README.md` — Next.js Auth0 + Vercel
- `core/README.md` — daemon OAuth + RPC
- `app/README.md` — Flutter sign-in UI
- `hub/.env.example`, `mcp/.env.example`, `web/.env.example`, `core/.env.example`
