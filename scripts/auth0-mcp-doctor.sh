#!/usr/bin/env bash
# Diagnose hosted-MCP OAuth against Auth0 without any secrets.
#
# Answers three questions the Auth0 tenant log cannot:
#   1. Does the MCP protected-resource metadata advertise what clients expect?
#   2. Does an Auth0 API exist whose Identifier is exactly the PRM resource?
#   3. Is the tenant "Resource Parameter Compatibility Profile" actually on?
#
# Probes are unauthenticated GETs to /authorize with a first-party client and a
# registered callback; Auth0 answers before any login happens, so nothing is
# consumed and no user session is created.
#
# Usage (from repo root):
#   ./scripts/auth0-mcp-doctor.sh
#   MCP_PUBLIC_URL=https://mcp.mutande.online ./scripts/auth0-mcp-doctor.sh
#
# Override the probe client (any first-party app + one of its Allowed Callback URLs):
#   PROBE_CLIENT_ID=... PROBE_REDIRECT_URI=... ./scripts/auth0-mcp-doctor.sh
set -euo pipefail

MCP_PUBLIC_URL="${MCP_PUBLIC_URL:-https://mcp.mutande.online}"
AUTH0_DOMAIN="${AUTH0_DOMAIN:-auth.mutande.online}"
# Mac native app (core/src/daemon/auth0_defaults.rs) + its loopback callback.
PROBE_CLIENT_ID="${PROBE_CLIENT_ID:-2cbPq8c2JelRxBRkvKlSHTmrM91ItUUm}"
PROBE_REDIRECT_URI="${PROBE_REDIRECT_URI:-http://127.0.0.1:8732/callback}"
BOGUS_AUDIENCE="https://bogus.mutande.invalid"

urlenc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }
urldec() { python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.argv[1]))' "$1"; }

# Location header of an /authorize probe with one extra query param.
authorize_location() {
  local extra="$1"
  local url="https://${AUTH0_DOMAIN}/authorize?client_id=${PROBE_CLIENT_ID}&response_type=code"
  url+="&redirect_uri=$(urlenc "$PROBE_REDIRECT_URI")&scope=openid%20email%20offline_access%20profile"
  url+="&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256&state=doctor"
  url+="&${extra}"
  urldec "$(curl -sS -o /dev/null -D - "$url" | tr -d '\r' | awk 'tolower($1)=="location:"{print $2; exit}')"
}

fail=0
note() { printf '  %s\n' "$1"; }

echo "== 1. Protected resource metadata (RFC 9728) =="
prm="$(curl -fsS "${MCP_PUBLIC_URL}/.well-known/oauth-protected-resource")" || {
  echo "  FAIL: PRM unreachable at ${MCP_PUBLIC_URL}"; exit 1;
}
echo "  $prm"
resource="$(printf '%s' "$prm" | python3 -c 'import json,sys;print(json.load(sys.stdin)["resource"])')"
as_url="$(printf '%s' "$prm" | python3 -c 'import json,sys;print(json.load(sys.stdin)["authorization_servers"][0])')"
note "resource             = ${resource}"
note "authorization_server = ${as_url}"
case "$resource" in
  https://*) [[ "$resource" == */ ]] && { note "FAIL: resource has a trailing slash — Auth0 API Identifiers must match exactly"; fail=1; } ;;
  *) note "FAIL: resource must be an absolute https URI (RFC 8707)"; fail=1 ;;
esac

echo
echo "== 2. Authorization server metadata =="
curl -fsS "https://${AUTH0_DOMAIN}/.well-known/oauth-authorization-server" \
  | python3 -c 'import json,sys;d=json.load(sys.stdin);print("  issuer:",d["issuer"]);print("  registration_endpoint:",d.get("registration_endpoint","(DCR OFF)"))'

echo
echo "== 3. Does an Auth0 API exist with Identifier == ${resource}? =="
loc="$(authorize_location "audience=$(urlenc "$resource")")"
case "$loc" in
  *"Service not found"*) note "FAIL: no Auth0 API has that exact Identifier."
                          note "Fix: Applications -> APIs -> Create API, Identifier ${resource} (no trailing slash)."; fail=1 ;;
  *"is not authorized to access resource server"*) note "OK: API exists (probe client just lacks a grant to it — expected)." ;;
  */u/login*)            note "OK: API exists and the probe client is authorized for it." ;;
  *)                     note "UNKNOWN: ${loc}"; fail=1 ;;
esac

echo
echo "== 4. Is Resource Parameter Compatibility Profile on? =="
# Discriminator: with the profile ON, Auth0 resolves ?resource= as the audience,
# so a nonexistent resource must fail "Service not found". With it OFF, resource
# is ignored and Auth0 falls through to the userinfo audience (login page).
loc="$(authorize_location "resource=$(urlenc "$BOGUS_AUDIENCE")")"
case "$loc" in
  *"Service not found"*) note "OK: tenant honours ?resource= (profile is ON)." ;;
  */u/login*)            note "FAIL: ?resource= is ignored — profile is OFF."
                          note "Auth0 then falls back to the userinfo audience, which third-party (DCR / tpc_) clients"
                          note "may not use: 'The userinfo audience is not allowed for third party clients.'"
                          note "Fix: Dashboard -> Settings -> Advanced -> Resource Parameter Compatibility Profile -> on -> Save."
                          note "(Tenant-wide setting. It is NOT on the API page.)"; fail=1 ;;
  *)                     note "UNKNOWN: ${loc}"; fail=1 ;;
esac

echo
echo "== 5. Sanity: does ?resource=${resource} reach login? =="
loc="$(authorize_location "resource=$(urlenc "$resource")")"
case "$loc" in
  */u/login*)            note "reaches Universal Login (inconclusive on its own — see step 4)" ;;
  *)                     note "$loc" ;;
esac

echo
if [[ "$fail" -eq 0 ]]; then
  echo "All checks passed. If ChatGPT still fails, check the Auth0 tenant log for the"
  echo "failed authorize and compare its 'audience' field against ${resource}."
else
  echo "Issues found — see FAIL lines above. Details: docs/AUTH0.md section 8."
fi
exit "$fail"
