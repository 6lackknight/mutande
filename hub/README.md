# Mutande Hub

Blind courier API on Deno Deploy: Hono + Deno KV (+ R2 for blobs in production).

Stores ciphertext envelopes, thread metadata, and public keys. Never stores private keys or plaintext.

## Local dev

```bash
export JWT_SECRET=dev-secret
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
| POST | `/v1/auth/register` | invite + handle + pubkey |
| POST | `/v1/auth/token` | refresh_token |
| GET | `/v1/auth/me` | Bearer JWT |
| GET | `/v1/contacts` | Bearer JWT |
| GET/POST | `/v1/threads` | Bearer JWT |
| GET | `/v1/threads/:id` | Bearer JWT |
| POST | `/v1/threads/:id/replies` | Bearer JWT |
| POST | `/v1/threads/:id/close` | Bearer JWT |
| CRUD | `/v1/drafts` | Bearer JWT |
| POST | `/v1/blobs/upload-url` | Bearer JWT |
| POST | `/v1/blobs/:id/download-url` | Bearer JWT |

Inline envelopes limited to ~60KB serialized. Blobs use R2 presigned PUT/GET when configured; otherwise mock `https://blobs.mutande.app/{id}` URLs with the same response shape. Per-org 500MB quota is tracked in KV.

## Env

| Variable | Required | Description |
|----------|----------|-------------|
| `JWT_SECRET` | prod | HS256 secret for access tokens |
| `R2_ACCOUNT_ID` | for real blobs | Cloudflare account id |
| `R2_ACCESS_KEY_ID` | for real blobs | R2 API token access key |
| `R2_SECRET_ACCESS_KEY` | for real blobs | R2 API token secret |
| `R2_BUCKET` | for real blobs | Bucket name |
| `R2_PUBLIC_BASE` | optional | Mock URL base when R2 is unset (default `https://blobs.mutande.app`) |

When any of `R2_ACCOUNT_ID` / `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` / `R2_BUCKET` is missing, the hub logs a clear warning and returns mock upload/download URLs so local tests work without Cloudflare.

## Deploy

```bash
deno task deploy
```

Set `JWT_SECRET` (and R2 vars for production blobs) in Deno Deploy project env.
