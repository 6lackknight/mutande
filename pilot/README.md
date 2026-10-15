# Pilot — 5 friends

Live Google Meet (~30–40 min). Goal per person:

1. **Self-collab** — their agents talk (personal `@all` / second host)
2. **Collab with Tawanda** — one real thread both ways

No web plaintext path. Mac alpha only: `/downloads/mutande-alpha.dmg` on prod web.

## Session flow

1. Install alpha → Auth0 → join org  
2. Connect AI host (Cursor / Claude Desktop / ChatGPT desktop)  
3. Self-collab ping  
4. Ping with you  
5. Ask: would you leave the Mac app open for real cofounder work?

Gemini Meet notes are backup. After each call, paste into a new file under `sessions/`.

Weekly rollup (waitlist + Mixpanel + missing-data asks): `sessions/YYYY-MM-DD-weekly.md`. Latest: `sessions/2026-08-21-weekly.md`.

Onboarding UX spec: `ONBOARDING-DESIGN.md` (stepper, team roster, host detection).

Friends can also send **in-app feedback** (Settings → Feedback) — stored on the hub as Auth0-signed `POST /v1/feedback`. The marketing site **Join waitlist** survey lands in the same ops bucket via public `POST /v1/waitlist`.

### Local ops dashboard (preferred)

Charts + tables for feedback and waitlist. **Localhost only** — not part of the web deploy. Uses Auth0 login (same Native app as Mac).

**One-time Auth0 setup:** Native Application → Allowed Callback URLs, add:

```
http://127.0.0.1:3848/auth/callback
```

Also add `http://127.0.0.1:3848` to Allowed Logout URLs / Allowed Web Origins if Auth0 complains.

```bash
deno task --cwd pilot/ops start
# → http://127.0.0.1:3848 → Log in (Auth0 SuperAdmin)
```

`MUTANDE_OPS_PORT` overrides the port (default `3848`). Optional: `AUTH0_DOMAIN`, `AUTH0_NATIVE_CLIENT_ID`, `AUTH0_AUDIENCE`, `MUTANDE_HUB_URL`.

### Curl

```bash
# After signing in as org admin (use a short-lived access token)
curl -sS -H "Authorization: Bearer $TOKEN" \
  https://hub.mutande.online/v1/admin/feedback | jq .

curl -sS -H "Authorization: Bearer $TOKEN" \
  https://hub.mutande.online/v1/admin/waitlist | jq .
```

## After each call

```bash
cp pilot/TEMPLATE.md pilot/sessions/YYYY-MM-DD-firstname.md
```

Paste Gemini notes (or your own) under **Raw notes**. Fill the short fields at the top while it’s fresh. Optionally paste any in-app feedback quotes.

## After all 5

One path-focused sprint: fix blockers that hit **≥2** people. Ignore one-off polish until the path is boring.
