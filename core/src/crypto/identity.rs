use std::sync::Mutex;

use super::seal::device_public_from_secret;
use super::types::{DevicePubKey, DeviceSecretKey};

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum StoreError {
    #[error("identity not found")]
    NotFound,
    #[error("identity corrupt")]
    Corrupt,
    #[error("store failed")]
    Failed,
}

/// Seam for device secret persistence — Keychain in prod, memory in tests.
pub trait IdentityStore: Send + Sync {
    fn load_device_secret(&self) -> Result<DeviceSecretKey, StoreError>;
    fn device_public(&self) -> Result<DevicePubKey, StoreError>;
    fn save_device_keypair(
        &self,
        public: &DevicePubKey,
        secret: &DeviceSecretKey,
    ) -> Result<(), StoreError>;
}

/// Test adapter — real seam (two adapters justify the trait).
pub struct MemoryStore {
    pair: Mutex<Option<(DevicePubKey, DeviceSecretKey)>>,
}

impl MemoryStore {
    pub fn new() -> Self {
        Self {
            pair: Mutex::new(None),
        }
    }
}

impl Default for MemoryStore {
    fn default() -> Self {
        Self::new()
    }
}

impl IdentityStore for MemoryStore {
    fn load_device_secret(&self) -> Result<DeviceSecretKey, StoreError> {
        self.pair
            .lock()
            .map_err(|_| StoreError::Failed)?
            .as_ref()
            .map(|(_, sk)| sk.clone())
            .ok_or(StoreError::NotFound)
    }

    fn device_public(&self) -> Result<DevicePubKey, StoreError> {
        self.pair
            .lock()
            .map_err(|_| StoreError::Failed)?
            .as_ref()
            .map(|(pk, _)| *pk)
            .ok_or(StoreError::NotFound)
    }

    fn save_device_keypair(
        &self,
        public: &DevicePubKey,
        secret: &DeviceSecretKey,
    ) -> Result<(), StoreError> {
        *self.pair.lock().map_err(|_| StoreError::Failed)? =
            Some((*public, secret.clone()));
        Ok(())
    }
}

/// macOS Keychain adapter — secret only; public is derived.
#[cfg(target_os = "macos")]
pub struct KeychainIdentityStore {
    service: &'static str,
    account: &'static str,
    memory: MemoryStore,
}

#[cfg(target_os = "macos")]
impl KeychainIdentityStore {
    /// Keychain generic-password service — matches app reverse-DNS (`ai.mutande.app`).
    pub const SERVICE: &'static str = "ai.mutande.core";
    /// Pre-brand placeholder; read once then rewrite under [SERVICE].
    const LEGACY_SERVICE: &'static str = "xyz.mutande.core";
    pub const ACCOUNT: &'static str = "device-secret";

    pub fn new() -> Self {
        Self {
            service: Self::SERVICE,
            account: Self::ACCOUNT,
            memory: MemoryStore::new(),
        }
    }

    /// Load secret from Keychain into the in-memory cache (no-op if missing).
    pub fn load_from_keychain(&self) -> Result<(), StoreError> {
        use security_framework::passwords::get_generic_password;

        let (bytes, from_legacy) = match get_generic_password(self.service, self.account) {
            Ok(bytes) => (bytes, false),
            Err(e)
                if e.code() == security_framework_sys::base::errSecItemNotFound =>
            {
                match get_generic_password(Self::LEGACY_SERVICE, self.account) {
                    Ok(bytes) => (bytes, true),
                    Err(e)
                        if e.code() == security_framework_sys::base::errSecItemNotFound =>
                    {
                        return Ok(());
                    }
                    Err(_) => return Err(StoreError::Failed),
                }
            }
            Err(_) => return Err(StoreError::Failed),
        };

        if bytes.len() != 32 {
            return Err(StoreError::Corrupt);
        }
        let mut sk = [0u8; 32];
        sk.copy_from_slice(&bytes);
        let secret = DeviceSecretKey(sk);
        let public = device_public_from_secret(&secret);
        self.memory.save_device_keypair(&public, &secret)?;

        // Quiet rename: next prompts show `ai.mutande.core`, not `xyz…`.
        if from_legacy {
            let _ = self.persist_secret(&secret);
        }
        Ok(())
    }

    fn persist_secret(&self, secret: &DeviceSecretKey) -> Result<(), StoreError> {
        use security_framework::passwords::set_generic_password;

        // Create-or-update in place (SecItemAdd → SecItemUpdate on duplicate).
        // Never delete-then-set: a failed set after delete would lose the identity.
        set_generic_password(self.service, self.account, &secret.0).map_err(|_| StoreError::Failed)
    }
}

#[cfg(target_os = "macos")]
impl Default for KeychainIdentityStore {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(target_os = "macos")]
impl IdentityStore for KeychainIdentityStore {
    fn load_device_secret(&self) -> Result<DeviceSecretKey, StoreError> {
        self.memory.load_device_secret()
    }

    fn device_public(&self) -> Result<DevicePubKey, StoreError> {
        self.memory.device_public()
    }

    fn save_device_keypair(
        &self,
        public: &DevicePubKey,
        secret: &DeviceSecretKey,
    ) -> Result<(), StoreError> {
        if device_public_from_secret(secret) != *public {
            return Err(StoreError::Corrupt);
        }
        self.persist_secret(secret)?;
        self.memory.save_device_keypair(public, secret)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::{device_public_from_secret, seal, open};
    use crypto_box::aead::OsRng;
    use crypto_box::SecretKey;

    #[test]
    fn store_then_seal_open_via_loaded_secret() {
        let sk = SecretKey::generate(&mut OsRng);
        let pk = DevicePubKey(sk.public_key().to_bytes());
        let secret = DeviceSecretKey(sk.to_bytes());

        let store = MemoryStore::new();
        store.save_device_keypair(&pk, &secret).unwrap();

        let loaded = store.load_device_secret().unwrap();
        assert_eq!(store.device_public().unwrap(), device_public_from_secret(&loaded));

        let msg = b"draft encrypted to self";
        let env = seal(msg, &[pk]).unwrap();
        assert_eq!(open(&env, &loaded).unwrap(), msg);
    }
}
