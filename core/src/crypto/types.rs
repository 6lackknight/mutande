use std::fmt;

use serde::{Deserialize, Serialize};

/// X25519 public key for one registered device.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Debug)]
pub struct DevicePubKey(pub [u8; 32]);

/// X25519 secret key — never cross the daemon seam in logs or MCP.
#[derive(Clone, Serialize, Deserialize)]
pub struct DeviceSecretKey(pub [u8; 32]);

impl fmt::Debug for DeviceSecretKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("DeviceSecretKey([REDACTED])")
    }
}

/// Content encryption key wrapped for one recipient device.
#[derive(Clone, Serialize, Deserialize, Debug, PartialEq, Eq)]
pub struct Wrap {
    pub recipient: DevicePubKey,
    /// Ephemeral sender public key used for this crypto_box wrap.
    pub ephemeral_public: DevicePubKey,
    pub boxed_cek: Vec<u8>,
}

/// Hub-visible wire unit: one content ciphertext + per-device wraps.
/// For large payloads, `ciphertext` is empty and content lives in R2 (`blob_id` + `sha256`).
#[derive(Clone, Serialize, Deserialize, Debug, PartialEq, Eq)]
pub struct Envelope {
    pub version: u8,
    /// Nonce for content AEAD (ChaCha20-Poly1305).
    pub content_nonce: [u8; 12],
    pub ciphertext: Vec<u8>,
    pub wraps: Vec<Wrap>,
    /// R2 object id after client uploads sealed ciphertext via presigned PUT.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub blob_id: Option<String>,
    /// Hex SHA-256 of the blob ciphertext bytes.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sha256: Option<String>,
}

#[cfg(test)]
mod secret_debug_tests {
    use super::*;

    #[test]
    fn device_secret_key_debug_is_redacted() {
        let secret = DeviceSecretKey([7u8; 32]);
        let dbg = format!("{secret:?}");
        assert_eq!(dbg, "DeviceSecretKey([REDACTED])");
        assert!(!dbg.contains('7'));
    }
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum CryptoError {
    #[error("no recipients")]
    EmptyRecipients,
    #[error("duplicate recipient")]
    DuplicateRecipient,
    #[error("plaintext empty")]
    EmptyPlaintext,
    #[error("no wrap for this device")]
    NoWrapForSelf,
    #[error("open failed")]
    OpenFailed,
}
