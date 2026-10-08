//! Mutande core library — crypto, daemon IPC, hub client, MCP bridge.

pub mod address;
pub mod crypto;
pub use crypto::{CryptoError, DevicePubKey, DeviceSecretKey, Envelope, Wrap, open, seal};
pub mod cli_rpc;
pub mod daemon;
pub mod hub_client;
pub mod mcp;
