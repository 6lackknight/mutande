/**
 * Local-only pilot ops dashboard with Auth0 login (PKCE).
 * Prefer prod: https://mutande.online/admin/ops (web app, Auth0 SuperAdmin).
 * Binds 127.0.0.1 — never expose.
 *
 *   deno task start
 *   → http://127.0.0.1:3848  → Log in
 *
 * Auth0 Native app must allow callback:
 *   http://127.0.0.1:3848/auth/callback
 */

const HOST = "127.0.0.1";
const PORT = Number(Deno.env.get("MUTANDE_OPS_PORT") ?? "3848");
const ORIGIN = `http://${HOST}:${PORT}`;
const HUB = (Deno.env.get("MUTANDE_HUB_URL") ??
  "https://mutande.6lackknight.deno.net").replace(/\/$/, "");

const AUTH0_DOMAIN = (Deno.env.get("AUTH0_DOMAIN") ?? "auth.mutande.online")
  .replace(/^https?:\/\//, "")
  .replace(/\/$/, "");
const AUTH0_CLIENT_ID = Deno.env.get("AUTH0_NATIVE_CLIENT_ID") ??
  "2cbPq8c2JelRxBRkvKlSHTmrM91ItUUm";
const AUTH0_AUDIENCE = Deno.env.get("AUTH0_AUDIENCE") ??
  "https://hub.mutande.app";
const AUTH0_ISSUER = `https://${AUTH0_DOMAIN}/`;

const PUBLIC = new URL("./public/", import.meta.url);

const COOKIE_AT = "ops_at";
const COOKIE_PKCE = "ops_pkce";
const COOKIE_STATE = "ops_state";

function contentType(path: string): string {
  if (path.endsWith(".html")) return "text/html; charset=utf-8";
  if (path.endsWith(".js")) return "text/javascript; charset=utf-8";
  if (path.endsWith(".css")) return "text/css; charset=utf-8";
  return "application/octet-stream";
}

async function serveStatic(pathname: string): Promise<Response> {
  const rel = pathname === "/" ? "index.html" : pathname.replace(/^\//, "");
  if (rel.includes("..")) return new Response("Not found", { status: 404 });
  try {
    const file = await Deno.readFile(new URL(rel, PUBLIC));
    return new Response(file, {
      headers: {
        "content-type": contentType(rel),
        "cache-control": "no-store",
      },
    });
  } catch {
    return new Response("Not found", { status: 404 });
  }
}

function parseCookies(req: Request): Record<string, string> {
  const raw = req.headers.get("cookie") ?? "";
  const out: Record<string, string> = {};
  for (const part of raw.split(";")) {
    const i = part.indexOf("=");
    if (i < 0) continue;
    const k = part.slice(0, i).trim();
    const v = part.slice(i + 1).trim();
    if (k) out[k] = decodeURIComponent(v);
  }
  return out;
}

function cookie(
  name: string,
  value: string,
  opts: { maxAge?: number; clear?: boolean } = {},
): string {
  if (opts.clear) {
    return `${name}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`;
  }
  const max = opts.maxAge ?? 60 * 60 * 12;
  return `${name}=${encodeURIComponent(value)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${max}`;
}

function b64url(bytes: Uint8Array): string {
  let s = btoa(String.fromCharCode(...bytes));
  return s.replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function randomString(nbytes = 32): string {
  return b64url(crypto.getRandomValues(new Uint8Array(nbytes)));
}

async function sha256b64url(input: string): Promise<string> {
  const dig = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(input),
  );
  return b64url(new Uint8Array(dig));
}

function accessToken(req: Request): string | null {
  return parseCookies(req)[COOKIE_AT] || null;
}

async function startLogin(): Promise<Response> {
  const verifier = randomString(32);
  const state = randomString(16);
  const challenge = await sha256b64url(verifier);
  const params = new URLSearchParams({
    response_type: "code",
    client_id: AUTH0_CLIENT_ID,
    redirect_uri: `${ORIGIN}/auth/callback`,
    scope: "openid profile email offline_access",
    audience: AUTH0_AUDIENCE,
    state,
    code_challenge: challenge,
    code_challenge_method: "S256",
  });
  const headers = new Headers({ Location: `${AUTH0_ISSUER}authorize?${params}` });
  headers.append("Set-Cookie", cookie(COOKIE_PKCE, verifier, { maxAge: 600 }));
  headers.append("Set-Cookie", cookie(COOKIE_STATE, state, { maxAge: 600 }));
  return new Response(null, { status: 302, headers });
}

async function handleCallback(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const err = url.searchParams.get("error");
  if (err) {
    const desc = url.searchParams.get("error_description") ?? err;
    return new Response(`Auth0 error: ${desc}`, {
      status: 400,
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  }
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const cookies = parseCookies(req);
  if (!code || !state || state !== cookies[COOKIE_STATE]) {
    return new Response("Invalid OAuth state", { status: 400 });
  }
  const verifier = cookies[COOKIE_PKCE];
  if (!verifier) {
    return new Response("Missing PKCE verifier — try Log in again", {
      status: 400,
    });
  }

  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: AUTH0_CLIENT_ID,
    code,
    redirect_uri: `${ORIGIN}/auth/callback`,
    code_verifier: verifier,
  });
  const tokenRes = await fetch(`${AUTH0_ISSUER}oauth/token`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  const tokenJson = await tokenRes.json() as {
    access_token?: string;
    expires_in?: number;
    error?: string;
    error_description?: string;
  };
  if (!tokenRes.ok || !tokenJson.access_token) {
    return new Response(
      `Token exchange failed: ${tokenJson.error_description ?? tokenJson.error ?? tokenRes.status}`,
      { status: 400 },
    );
  }

  const maxAge = Math.max(60, Number(tokenJson.expires_in ?? 3600) - 60);
  const headers = new Headers({ Location: "/" });
  headers.append(
    "Set-Cookie",
    cookie(COOKIE_AT, tokenJson.access_token, { maxAge }),
  );
  headers.append("Set-Cookie", cookie(COOKIE_PKCE, "", { clear: true }));
  headers.append("Set-Cookie", cookie(COOKIE_STATE, "", { clear: true }));
  return new Response(null, { status: 302, headers });
}

function handleLogout(): Response {
  const headers = new Headers({ Location: "/" });
  headers.append("Set-Cookie", cookie(COOKIE_AT, "", { clear: true }));
  headers.append("Set-Cookie", cookie(COOKIE_PKCE, "", { clear: true }));
  headers.append("Set-Cookie", cookie(COOKIE_STATE, "", { clear: true }));
  return new Response(null, { status: 302, headers });
}

async function proxyAdmin(path: string, req: Request): Promise<Response> {
  const token = accessToken(req);
  if (!token) {
    return Response.json(
      { error: "Not signed in", login: "/auth/login" },
      { status: 401 },
    );
  }
  let upstream: Response;
  try {
    upstream = await fetch(`${HUB}${path}`, {
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${token}`,
      },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return Response.json(
      { error: `Hub unreachable (${HUB}): ${message}` },
      { status: 503 },
    );
  }
  const text = await upstream.text();
  return new Response(text, {
    status: upstream.status,
    headers: {
      "content-type": upstream.headers.get("content-type") ??
        "application/json",
      "cache-control": "no-store",
    },
  });
}

// Kill previous instance on same port if we're restarting.
try {
  const prev = Deno.env.get("MUTANDE_OPS_RESTART");
  void prev;
} catch { /* ignore */ }

const server = Deno.serve(
  { hostname: HOST, port: PORT },
  async (req) => {
    const url = new URL(req.url);
    if (url.hostname !== "127.0.0.1" && url.hostname !== "localhost") {
      return new Response("Localhost only", { status: 403 });
    }

    if (req.method === "GET" && url.pathname === "/auth/login") {
      return startLogin();
    }
    if (req.method === "GET" && url.pathname === "/auth/callback") {
      return handleCallback(req);
    }
    if (req.method === "GET" && url.pathname === "/auth/logout") {
      return handleLogout();
    }
    if (req.method === "GET" && url.pathname === "/api/config") {
      return Response.json({
        hub: HUB,
        loggedIn: Boolean(accessToken(req)),
        auth0Domain: AUTH0_DOMAIN,
        port: PORT,
      });
    }
    if (req.method === "GET" && url.pathname === "/api/feedback") {
      return proxyAdmin("/v1/admin/feedback", req);
    }
    if (req.method === "GET" && url.pathname === "/api/waitlist") {
      return proxyAdmin("/v1/admin/waitlist", req);
    }
    if (req.method === "GET") {
      return serveStatic(url.pathname);
    }
    return new Response("Method not allowed", { status: 405 });
  },
);

console.log(`mutande ops → ${ORIGIN}`);
console.log(`hub          → ${HUB}`);
console.log(`auth0        → ${AUTH0_DOMAIN} (native PKCE)`);
console.log(`callback     → ${ORIGIN}/auth/callback  (must be in Auth0 Native allowed callbacks)`);

await server.finished;
