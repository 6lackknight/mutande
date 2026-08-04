use anyhow::Result;
use clap::{Parser, Subcommand};
use mutande_core::daemon;
use mutande_core::mcp;
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(name = "mutande-core", about = "Mutande E2E daemon and MCP bridge")]
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

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

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
