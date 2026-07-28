# Mutande Hub

Blind courier API on Deno Deploy: Hono + Deno KV (+ R2 for blobs in production).

Stores ciphertext envelopes, thread metadata, and public keys. Never stores private keys or plaintext.

Auth is **Auth0-first**: the hub validates Auth0 access tokens via JWKS. Self-serve onboarding is create-team or join-with-invite.

Tenant / app setup (API, web, Mac, env vars): see [`docs/AUTH0.md`](../docs/AUTH0.md).

**Prod URLs:** hub `https://mutande.6lackknight.deno.net`; web `https://mutande.vercel.app` (until `mutande.ai`).

## Local dev

```bash
export AUTH0_DOMAIN=your-tenant.us.auth0.com
export AUTH0_AUDIENCE=https://hub.mutande.app
deno task dev
curl http://localhost:8000/health
```

## Tests

```bash
deno task test
deno task check
```

## API (v1)

| Method | Path | Auth |
|--------|------|------|
| GET | `/health` | — |
| GET | `/v1/me` | Auth0 Bearer |
| GET | `/v1/auth/me` | Auth0 Bearer (alias) |
| POST | `/v1/orgs` | Auth0 Bearer (not yet onboarded) |
| POST | `/v1/onboarding/join` | Auth0 Bearer (not yet onboarded) |
| POST | `/v1/devices` | Auth0 Bearer (onboarded) |
| GET/POST | `/v1/admin/invites` | Auth0 Bearer + `org_admin` |
| GET | `/v1/contacts` | Auth0 Bearer (onboarded) |
| GET/POST | `/v1/agents` | Auth0 Bearer (onboarded); `?handle=` for recipient slug autocomplete |
| GET/PUT | `/v1/agents/router` | Auth0 Bearer — default agent + routing rules |
| PUT | `/v1/agents/default` | Auth0 Bearer — set default agent |
| PATCH | `/v1/agents/:agentId` | Auth0 Bearer — rename slug (same `agent_id`) |
| GET/POST | `/v1/threads` | Auth0 Bearer (onboarded) |
| GET | `/v1/threads/:id` | Auth0 Bearer (onboarded) |
| POST | `/v1/threads/:id/replies` | Auth0 Bearer (onboarded) |
| POST | `/v1/threads/:id/close` | Auth0 Bearer (onboarded) |
| CRUD | `/v1/drafts` | Auth0 Bearer (onboarded) |
| POST | `/v1/blobs/upload-url` | Auth0 Bearer (onboarded) |
| POST | `/v1/blobs/:id/download-url` | Auth0 Bearer (onboarded) |

### Auth0 contract (summary)

1. Client sends `Authorization: Bearer <Auth0 access token>`.
2. `GET /v1/me` → `{ auth0_sub, email?, onboarded, needs_onboarding?, user?, org? }`.
3. If not `onboarded`:
   - **Create team:** `POST /v1/orgs` `{ slug, name?, handle? }` → creator becomes `org_admin`; default handle `email-local@slug`.
   - **Join:** `POST /v1/onboarding/join` `{ invite_code, handle? }` → `member`; invite burned.
4. `POST /v1/devices` `{ pubkey, platform }` (`macos` \| `ios` \| `web`).
5. Org admins: `GET/POST /v1/admin/invites` (hub stores codes; email delivery is web-side / Plunk).

Inline envelopes limited to ~60KB serialized. Blobs use R2 presigned PUT/GET when configured; otherwise mock `https://blobs.mutande.app/{id}` URLs with the same response shape. Per-org 500MB quota is tracked in KV.

## Env

| Variable | Required | Description |
|----------|----------|-------------|
| `AUTH0_DOMAIN` | prod | Auth0 tenant domain (JWKS issuer host) |
| `AUTH0_AUDIENCE` | prod | Auth0 API audience for access tokens |
| `R2_ACCOUNT_ID` | for real blobs | Cloudflare account id |
| `R2_ACCESS_KEY_ID` | for real blobs | R2 API token access key |
| `R2_SECRET_ACCESS_KEY` | for real blobs | R2 API token secret |
| `R2_BUCKET` | for real blobs | Bucket name |
| `R2_PUBLIC_BASE` | optional | Mock URL base when R2 is unset (default `https://blobs.mutande.app`) |

When any of `R2_ACCOUNT_ID` / `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` / `R2_BUCKET` is missing, the hub logs a clear warning and returns mock upload/download URLs so local tests work without Cloudflare.

## Deploy

1. Copy values from `hub/.env.example` (or a local `hub/.env`) into the Deno Deploy project **Settings → Environment Variables**:
   `AUTH0_DOMAIN`, `AUTH0_AUDIENCE`, plus R2 vars.
2. Then:

```bash
cd hub && deno task deploy
```

`deployctl` targets project `mutande`. Do not commit secrets.
