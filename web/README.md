# Mutande web

Next.js (App Router) front-end for Auth0 sign-in, org onboarding, admin invites, and pilot ops (feedback/waitlist). Deployed on Vercel. No E2E mail in the browser — metadata and invites only.

**Prod web:** [https://mutande.online](https://mutande.online) (canonical until `mutande.ai`). Optional aliases: `mutande.vercel.app`, `mutande-web.vercel.app`.

## Local run

```bash
cd web
cp .env.example .env.local
# fill Auth0 + hub vars
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Auth0 setup

Full checklist (API + Regular Web + Native Mac + Database): [`docs/AUTH0.md`](../docs/AUTH0.md).

Short path for this app:

1. Create a **Regular Web Application** (separate from the Mac Native app).
2. Enable **Password** and **Email (passwordless)** on the Database connection; enable that connection on this app.
3. Application URLs:
   - Callback: `http://localhost:3000/auth/callback` and `https://mutande.online/auth/callback`
   - Logout: `http://localhost:3000` and `https://mutande.online` (plus `/auth/logout`)
   - Web Origins: same origins
4. Create an **API** whose Identifier matches `AUTH0_AUDIENCE` / hub `AUTH0_AUDIENCE` (e.g. `https://hub.mutande.app`).
5. Authorize the web app for that API (RBAC optional for v1).
6. Copy Domain, Client ID, Client Secret into `.env.local`. Generate `AUTH0_SECRET` with `openssl rand -hex 32`.

SDK routes are mounted by `src/proxy.ts`: `/auth/login`, `/auth/logout`, `/auth/callback`, `/auth/access-token`.

## Env vars

| Variable | Required | Notes |
|----------|----------|--------|
| `AUTH0_DOMAIN` | yes | Tenant domain |
| `AUTH0_CLIENT_ID` | yes | Web app |
| `AUTH0_CLIENT_SECRET` | yes | Web app |
| `AUTH0_SECRET` | yes | Session cookie encryption |
| `AUTH0_AUDIENCE` | yes | Hub API audience |
| `APP_BASE_URL` | recommended | Local `http://localhost:3000`; production `https://mutande.online` (until `mutande.ai`); omit on Vercel previews to infer host |
| `MUTANDE_HUB_URL` | no | Default `https://mutande.6lackknight.deno.net` |
| `PLUNK_API_KEY` | no | Invite email; if unset, create + copy link still works |

## Hub contract

Bearer Auth0 access token (audience) on:

- `GET /v1/auth/me`
- `POST /v1/orgs` `{ slug, name?, handle? }`
- `POST /v1/onboarding/join` `{ invite_code, handle }`
- `GET` / `POST /v1/admin/invites`
- `GET /v1/admin/feedback`
- `GET /v1/admin/waitlist`

Typed client: `src/lib/hub.ts`. Network / 4xx–5xx surface as friendly UI errors so the app remains usable while hub Auth0 routes finish landing.

## Vercel deploy

1. Import the monorepo; set **Root Directory** to `web`.
2. Framework: Next.js (auto).
3. Add the env vars above. Set production `APP_BASE_URL=https://mutande.online` and Auth0 callbacks/logout/web origins for that host.
4. Enable **Web Analytics** in the Vercel project (Analytics → Enable). The app mounts `@vercel/analytics` in the root layout.
5. Deploy. Production host: `https://mutande.online` until `mutande.ai`.

## Structure

```
web/
  src/
    app/                 # pages + server actions
    components/          # forms + UI
    lib/                 # auth0, hub, plunk, session
    proxy.ts             # Auth0 middleware (Next 16)
  .env.example
```

## Pages

| Path | Purpose |
|------|---------|
| `/` | Landing |
| `/login` | Auth0 entry |
| `/signup` | Create team vs invite |
| `/onboarding/create` | Org slug / name / handle |
| `/join?invite=` | Join flow |
| `/dashboard` | Handle, org, download CTA |
| `/admin/invites` | List/create invites, copy link, Plunk email |
| `/admin/ops` | Pilot feedback + waitlist charts (Auth0 SuperAdmin) |
