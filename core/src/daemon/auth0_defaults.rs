//! Built-in Auth0 / hub defaults for Mac native login.
//!
//! Env vars and RPC params override these. Domains/client ids may change later;
//! keep this module as the single source for compile-time fallbacks.

/// Auth0 tenant host (no scheme).
pub const AUTH0_DOMAIN: &str = "auth.mutande.online";

/// Auth0 Native Application client id (public; no secret).
pub const AUTH0_NATIVE_CLIENT_ID: &str = "2cbPq8c2JelRxBRkvKlSHTmrM91ItUUm";

/// Auth0 API identifier (must match hub `AUTH0_AUDIENCE`).
pub const AUTH0_AUDIENCE: &str = "https://hub.mutande.app";

/// Production Deno Deploy hub.
pub const HUB_URL: &str = "https://mutande.6lackknight.deno.net";
