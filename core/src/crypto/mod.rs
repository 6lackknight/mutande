//! E2E seal/open — one ciphertext, N device wraps.

mod blob;
mod identity;
mod safety;
mod seal;
mod types;

pub use blob::{
    SealedBlob, open_from_bytes, open_from_path, recipients_for_blob, seal_to_temp, with_blob_id,
};
pub use identity::{IdentityStore, MemoryStore, StoreError};

#[cfg(target_os = "macos")]
pub use identity::KeychainIdentityStore;
pub use safety::{
    SAFETY_URI_PREFIX, fingerprints_match, parse_safety_uri, safety_number, safety_uri,
};
pub use seal::{device_public_from_secret, open, seal};
pub use types::{CryptoError, DevicePubKey, DeviceSecretKey, Envelope, Wrap};
