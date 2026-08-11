# Auth0 setup (Mutande)

Free-tier Auth0 tenant for hub (API tokens), Vercel web (Regular Web App), and macOS (Native App). One API audience; two applications.

Canonical audience in this repo: `https://hub.mutande.app` (Auth0 API Identifier). Any URI works if hub, web, and Mac all use the same value.

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
exports.onExecutePostLogin = async (event, api) => {
  const namespace = "https://hub.mutande.app";
  const roles = event.authorization?.roles;
  if (roles?.length) {
    // Access token → hub + web API gates. ID token → session.user for web nav.
    api.accessToken.setCustomClaim(`${namespace}/roles`, roles);
    api.idToken.setCustomClaim(`${namespace}/roles`, roles);
  }
};
```

Enable **RBAC** on the Auth0 API (`https://hub.mutande.app`) so `event.authorization.roles` is populated. Hub/web also accept `https://mutande.app/roles`, `https://mutande.online/roles`, and bare `roles`. Override allowed role names/ids with hub env `MUTANDE_PLATFORM_ADMIN_ROLES` (comma-separated; default `SuperAdmin,rol_jsa0BZq7uzz2K4RG`).

After assigning the role or changing the Action, users must **sign out and sign in** so a fresh access token includes the claim. Org invites stay gated by hub `org_admin`.

## 8. Hosted MCP (ChatGPT web / Claude.ai) — L0

**Prod status:** live at `https://mcp.mutande.online` (`mcp/` package). Resource Parameter Compatibility, Include Issuer in Authorization Responses, domain-level connections, and DCR or manual ChatGPT/Claude clients are **already configured**. This section is the operator checklist if you rebuild a tenant or debug OAuth — do not re-apply blindly on a working prod tenant.

Web hosts connect **to us**; identity is the same Auth0 account as Mac/hub. No platform JWTs in v1.

**End users adding a connector:** [`docs/HOSTED-MCP.md`](HOSTED-MCP.md) (URL + OAuth + tool expectations). Package/redeploy: [`mcp/README.md`](../mcp/README.md).

### Tenant toggles (MCP clients)

Dashboard → **Settings → Advanced**:

1. **Resource Parameter Compatibility Profile** — on  
2. **Include Issuer in Authorization Responses** — on  

Promote Username-Password (and any social connections MCP clients should use) to **domain-level** so third-party apps can authenticate (`is_domain_connection: true`).

### Audience (L0 default)

Keep a **single** API Identifier `https://hub.mutande.app`. Hosted MCP validates that audience and forwards the same Bearer token to hub (`POST /v1/agents/connect/mcp`, inbox / thread APIs). No OBO exchange in L0.

Optional later (stronger resource indicators):

| Field | Value |
|-------|--------|
| Extra API Identifier | `https://mcp.mutande.online` |
| MCP env `AUTH0_MCP_AUDIENCE` | same |
| Token path | OBO / token exchange MCP → hub audience |

### Client registration

MCP clients (ChatGPT, Claude.ai, MCP Inspector) need an Auth0 application:

- Prefer **Dynamic Client Registration** for third-party hosts, **or**
- Manually register each host’s redirect URIs (Auth0 docs: *Register your MCP Client Application* / CIMD).

Grant access to the Mutande Hub API (`https://hub.mutande.app`). Grant types: Authorization Code + PKCE, Refresh Token, Offline Access.

### Env (Deno Deploy project `mutande-mcp`)

| Variable | Notes |
|----------|--------|
| `AUTH0_DOMAIN` | `auth.mutande.online` |
| `AUTH0_AUDIENCE` | `https://hub.mutande.app` |
| `MCP_PUBLIC_URL` | `https://mcp.mutande.online` |
| `MUTANDE_HUB_URL` | `https://hub.mutande.online` |
| `MCP_DEFAULT_AGENT_SLUG` | default `chatgpt` |

Hub (separate Deploy project) must keep **`APP_ENVELOPE_KEY`** set in prod for app_envelope mail at rest — not an MCP env var.

Redeploy MCP: `cd mcp && deno task deploy`.

## See also

- [`docs/HOSTED-MCP.md`](HOSTED-MCP.md) — ChatGPT / Claude connector (end user)
- `hub/README.md` — API routes + deploy
- `mcp/README.md` — hosted MCP package, tools, redeploy
- `web/README.md` — Next.js Auth0 + Vercel
- `core/README.md` — daemon OAuth + RPC
- `app/README.md` — Flutter sign-in UI
- `hub/.env.example`, `mcp/.env.example`, `web/.env.example`, `core/.env.example`
