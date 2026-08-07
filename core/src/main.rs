use std::borrow::Cow;
use std::time::Duration;

use anyhow::Result;
use clap::{Parser, Subcommand};
use mutande_core::daemon;
use mutande_core::mcp;
use tracing_subscriber::EnvFilter;
use tracing_subscriber::prelude::*;

#[derive(Parser)]
#[command(
    name = "mutande-core",
    about = "Mutande E2E daemon and MCP bridge",
    version
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Run background daemon (keys, crypto, hub API)
    Serve {
        #[arg(long, default_value = daemon::DEFAULT_SOCKET)]
        socket: String,
        /// HTTP JSON-RPC bridge for Flutter (POST /rpc). Required on Windows. Empty disables on Unix.
        #[arg(long, default_value = daemon::DEFAULT_HTTP_BIND)]
        http_bind: String,
    },
    /// MCP stdio server — forwards to running daemon
    Mcp,
}

/// Resolve GlitchTip DSN: `MUTANDE_SENTRY_DSN` → `SENTRY_DSN` → hardcoded default.
/// Empty string disables reporting.
fn resolve_sentry_dsn() -> Option<String> {
    for key in ["MUTANDE_SENTRY_DSN", "SENTRY_DSN"] {
        if let Ok(v) = std::env::var(key) {
            let trimmed = v.trim();
            if trimmed.is_empty() {
                return None;
            }
            return Some(trimmed.to_string());
        }
    }
    Some(daemon::DEFAULT_SENTRY_DSN.to_string())
}

fn sentry_smoke_enabled() -> bool {
    matches!(
        std::env::var("SENTRY_SMOKE").as_deref(),
        Ok("1") | Ok("true") | Ok("TRUE") | Ok("yes")
    )
}

fn init_sentry(smoke: bool) -> sentry::ClientInitGuard {
    let dsn = resolve_sentry_dsn();
    sentry::init(sentry::ClientOptions {
        dsn: dsn.and_then(|s| s.parse().ok()),
        release: sentry::release_name!(),
        traces_sample_rate: if smoke { 1.0 } else { 0.01 },
        send_default_pii: false,
        debug: smoke,
        environment: Some(Cow::Borrowed(if smoke { "smoke" } else { "production" })),
        shutdown_timeout: Duration::from_secs(5),
        ..Default::default()
    })
}

fn run_sentry_smoke() {
    let tx = sentry::start_transaction(sentry::TransactionContext::new(
        "glitchtip.smoke",
        "smoke",
    ));
    sentry::configure_scope(|scope| scope.set_span(Some(tx.clone().into())));
    let version = env!("CARGO_PKG_VERSION");
    sentry::capture_message(
        &format!("mutande-core GlitchTip smoke ({version})"),
        sentry::Level::Info,
    );
    tx.set_status(sentry::protocol::SpanStatus::Ok);
    tx.finish();
    if let Some(client) = sentry::Hub::current().client() {
        client.flush(Some(Duration::from_secs(5)));
    }
    eprintln!("SENTRY_SMOKE: message + transaction flushed");
}

#[tokio::main]
async fn main() -> Result<()> {
    let smoke = sentry_smoke_enabled();
    let _guard = init_sentry(smoke);

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::fmt::layer()
                .with_filter(EnvFilter::from_default_env()),
        )
        .with(sentry_tracing::layer())
        .init();

    if smoke {
        run_sentry_smoke();
        return Ok(());
    }

    match Cli::parse().command {
        Commands::Serve { socket, http_bind } => {
            let http = if http_bind.is_empty() {
                None
            } else {
                Some(http_bind.as_str())
            };
            daemon::run(&socket, http).await
        }
        Commands::Mcp => mcp::run_stdio().await,
    }
}
