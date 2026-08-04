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

Friends can also send **in-app feedback** (Settings → Feedback) — stored on the hub as Auth0-signed `POST /v1/feedback`. The marketing site **Join waitlist** survey lands in the same ops bucket via public `POST /v1/waitlist`. Read as org admin:

```bash
# After signing in as org admin (use a short-lived access token)
curl -sS -H "Authorization: Bearer $TOKEN" \
  https://mutande.6lackknight.deno.net/v1/admin/feedback | jq .

curl -sS -H "Authorization: Bearer $TOKEN" \
  https://mutande.6lackknight.deno.net/v1/admin/waitlist | jq .
```

## After each call

```bash
cp pilot/TEMPLATE.md pilot/sessions/YYYY-MM-DD-firstname.md
```

Paste Gemini notes (or your own) under **Raw notes**. Fill the short fields at the top while it’s fresh. Optionally paste any in-app feedback quotes.

## After all 5

One path-focused sprint: fix blockers that hit **≥2** people. Ignore one-off polish until the path is boring.
