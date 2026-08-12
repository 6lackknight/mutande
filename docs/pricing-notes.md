# Pricing notes

Running cost / plan-limit notes as we hit them. Not a formal budget — operator scratchpad so we don’t re-learn the same walls.

Last updated: 2026-08-12

---

## Deno Deploy

**Hit:** Free tier limit → had to **upgrade** (paid plan) to keep shipping hub / hosted MCP.

| Surface | Project (approx) | Notes |
|---------|------------------|--------|
| Hub | `mutande` → `hub.mutande.online` | Deno Deploy |
| Hosted MCP | `mutande-mcp` → `mcp.mutande.online` | Deno Deploy |

**Action taken:** Upgraded off free tier after hitting the limit.

**Follow-ups:** Record plan name, monthly $, and what metric tripped the limit (GB-hrs / requests / isolates) when we have the invoice handy.

---

## Auth0 (tenant `chevrondigital` / `auth.mutande.online`)

**Hit:** Free-tier **Applications** cap (**10** apps / tenant). Not a user (MAU) limit.

`POST https://auth.mutande.online/oidc/register` then returns **403** `too_many_entities`. ChatGPT/Claude surface that as connector registration failure (`ofid_…`).

### How slots work

- **1 Application** ≈ one OAuth client (web, native, M2M, or DCR third-party `tpc_…`).
- Hosted MCP hosts (ChatGPT, Claude, …) each **Dynamic Client Registration** → **1 third-party app** per host product, not per end user.
- Many humans can sign in through the same ChatGPT/Claude client once it exists.

### Budget (free, 10 apps)

Keep first-party mutande:

| Keep | Type |
|------|------|
| Mutande Web | Regular Web |
| Mutande Mac | Native |

That leaves **8 slots for third-party / other** apps (ChatGPT, Claude, future hosts, plus any leftover Default App / My App / VEXXS / probes we haven’t deleted).

If we also keep **iOS** Native, third-party headroom drops to **7**.

### Snapshot (2026-08-12) — 10/10 filled

| App | Type | Keep? |
|-----|------|--------|
| ChatGPT (`tpc_…`) | Third-party | Yes (hosted MCP) |
| Claude (`tpc_…`) | Third-party | Yes (hosted MCP) |
| Mutande Web | Regular Web | Yes |
| Mutande Mac | Native | Yes |
| iOS | Native | Only if shipping |
| Mutande Hosted MCP (Test) | M2M | Delete if unused |
| Default App | Generic | Delete |
| My App | Regular Web | Delete |
| Web App | Regular Web | Delete |
| VEXXS | M2M | Delete or move off this tenant |

**Implication:** On free Auth0 we can support about **8 third-party MCP host clients** after web + Mac — but only if we don’t leave junk apps around. Re-adding connectors / DCR probes burns slots.

**Mitigations:**

1. Delete unused Applications (free slots immediately).
2. Prefer **CIMD** / fewer DCR creations over open re-register loops (`docs/AUTH0.md` §8).
3. Upgrade Auth0 if we need more than ~8 host products or can’t stay clean.
4. Don’t put unrelated products (e.g. VEXXS) on the mutande Auth0 tenant.

**Follow-ups:** Note Auth0 plan / $ when we upgrade; confirm exact free Application limit if Auth0 changes it.

---

## Other (fill in as we hit them)

| Service | Trigger | Plan / $ | Notes |
|---------|---------|----------|--------|
| Cloudflare R2 (hub blobs / downloads) | | | |
| Vercel (web) | | | |
| GlitchTip | | | Projects: Flutter 26609, core 26610, hub 26611, mcp 26806 |
| Mixpanel | | | |
| Auth0 MAU | | | Separate from Applications cap |

---

## Related docs

- Auth0 DCR / connector troubleshooting: [`AUTH0.md`](AUTH0.md) §8
- Hosted MCP end-user setup: [`HOSTED-MCP.md`](HOSTED-MCP.md)
