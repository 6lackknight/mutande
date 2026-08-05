# Windows alpha release

Windows builds **cannot** run on macOS. Use GitHub Actions; the workflow
uploads the zip to the **same R2 bucket** as Mac DMGs.

## Flow

1. Push the commit you want built (Actions checks out GitHub, not your laptop).
2. **Actions** → **Release Windows alpha** → **Run workflow**
3. Jobs:
   - `build` — Flutter + core → `mutande-alpha-windows.zip` (artifact, 14 days)
   - `publish-r2` — `scripts/upload-downloads-r2.sh` → `mutande-releases`
4. Public URL: `https://downloads.mutande.online/mutande-alpha-windows.zip`
5. Site gate: set Vercel `NEXT_PUBLIC_WIN_ZIP_PUBLISHED=1` (and version if needed)

## Repo secrets (required for `publish-r2`)

| Secret | Notes |
|--------|--------|
| `R2_ACCOUNT_ID` | Cloudflare account id |
| `R2_DOWNLOADS_ACCESS_KEY_ID` | R2 S3 key **scoped to `mutande-releases`** |
| `R2_DOWNLOADS_SECRET_ACCESS_KEY` | Matching secret |

Do **not** reuse hub `mutande-blobs` keys — they get `AccessDenied` on releases.
Create an R2 API token with Object Read & Write on `mutande-releases` only.
Access Key ID = token id; Secret = SHA-256 of the token value (Cloudflare R2 docs).

Mac local uploads use the same script + preferred `R2_DOWNLOADS_*` env vars
(see `hub/.env` or export before `./scripts/upload-downloads-r2.sh`).

## SmartScreen

The zip is **unsigned**. Users choose **More info → Run anyway**. Authenticode deferred.

Mac notarized DMGs: `scripts/release-macos-dmg.sh` then the same upload script.
