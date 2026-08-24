#!/usr/bin/env bash
# Install mutande-core on Linux (Debian 12/13 x86_64) and wire Grok stdio MCP.
# Run on the Grok Bot computer:
#   curl -fsSL https://downloads.mutande.online/install-linux-sidecar.sh | bash
set -euo pipefail

BASE="${MUTANDE_DOWNLOADS_BASE:-https://downloads.mutande.online}"
ARCH="$(uname -m)"
OS="$(uname -s)"
if [[ "$OS" != "Linux" ]]; then
  echo "error: Linux only (got $OS)" >&2
  exit 1
fi
if [[ "$ARCH" != "x86_64" && "$ARCH" != "amd64" ]]; then
  echo "error: x86_64 only (got $ARCH). This build targets Debian 13 x86_64 / glibc." >&2
  exit 1
fi

BIN_URL="${MUTANDE_CORE_URL:-${BASE}/mutande-core-linux-x86_64}"
DEST_DIR="${HOME}/.mutande/bin"
DEST="${DEST_DIR}/mutande-core"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

mkdir -p "$DEST_DIR" "${HOME}/.mutande"
chmod 700 "${HOME}/.mutande" "$DEST_DIR" 2>/dev/null || true

echo "==> download ${BIN_URL}"
curl -fsSL "$BIN_URL" -o "$TMP"
chmod 755 "$TMP"
install -m 755 "$TMP" "$DEST"

echo "==> preflight"
"$DEST" --help >/dev/null

rpc() {
  local token="$1"
  local body="$2"
  curl -sS -X POST "http://127.0.0.1:3847/rpc" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "$body"
}

healthy() {
  local token="$1"
  rpc "$token" '{"jsonrpc":"2.0","id":1,"method":"health"}' 2>/dev/null | grep -q '"ok":true'
}

if [[ ! -f "${HOME}/.mutande/daemon_http_token" ]]; then
  # Serve creates the token on first start.
  true
fi

if [[ -f "${HOME}/.mutande/daemon_http_token" ]] && TOKEN="$(cat "${HOME}/.mutande/daemon_http_token")" && healthy "$TOKEN"; then
  echo "==> daemon already running"
else
  echo "==> start mutande-core serve"
  nohup "$DEST" serve >>"${HOME}/.mutande/core.log" 2>&1 &
  for _ in $(seq 1 25); do
    if [[ -f "${HOME}/.mutande/daemon_http_token" ]]; then
      TOKEN="$(cat "${HOME}/.mutande/daemon_http_token")"
      if healthy "$TOKEN"; then
        break
      fi
    fi
    sleep 0.2
  done
  TOKEN="$(cat "${HOME}/.mutande/daemon_http_token")"
  healthy "$TOKEN" || {
    echo "error: daemon did not become healthy. See ~/.mutande/core.log" >&2
    exit 1
  }
fi

echo "==> connect_host grok + install_skill grok"
rpc "$TOKEN" '{"jsonrpc":"2.0","id":2,"method":"connect_host","params":{"host":"grok"}}'
echo
rpc "$TOKEN" '{"jsonrpc":"2.0","id":3,"method":"install_skill","params":{"host":"grok"}}'
echo

cat <<EOF

mutande-core is at ${DEST}
Grok MCP: ~/.grok/config.toml (stdio → mutande-core mcp, slug grok)

Sign in on this machine (Auth0 loopback). Take over the Agent Computer browser if xdg-open does not:

  curl -sS -X POST http://127.0.0.1:3847/rpc \\
    -H "Authorization: Bearer \$(cat ~/.mutande/daemon_http_token)" \\
    -H "Content-Type: application/json" \\
    -d '{"jsonrpc":"2.0","id":4,"method":"auth_login","params":{"hub_url":"https://hub.mutande.online"}}'

Then reload Grok Bot plugins. Address will be you@org/grok.

EOF
