# Linux sidecar (Grok Bot / Debian)

`mutande-core` for **Linux x86_64**, glibc 2.35+ (Ubuntu 22.04, Debian 12 bookworm, Debian 13 trixie). No Flutter app — daemon + stdio MCP only.

## Flow

1. Push the commit to build.
2. **Actions** → **Release Linux sidecar** → **Run workflow**
3. Jobs:
   - `build` on `ubuntu-22.04` → `mutande-core-linux-x86_64`
   - `publish-r2` → `mutande-releases`
4. Public URLs:
   - `https://downloads.mutande.online/mutande-core-linux-x86_64`
   - `https://downloads.mutande.online/install-linux-sidecar.sh`

On the Grok Bot computer:

```bash
curl -fsSL https://downloads.mutande.online/install-linux-sidecar.sh | bash
```

Then `auth_login` on that machine (Auth0 loopback — take over the Agent Computer browser). `connect_host grok` writes `~/.grok/config.toml` (`mutande-core mcp`, slug `grok`).

Same R2 secrets as Windows (`R2_ACCOUNT_ID`, `R2_DOWNLOADS_ACCESS_KEY_ID`, `R2_DOWNLOADS_SECRET_ACCESS_KEY`).
