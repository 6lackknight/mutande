//! Satellite crypto helpers — seal large payloads to a temp ciphertext file for R2 upload.
//! Shares CEK/wrap path with inline `seal`/`open`; blob ciphertext is not stored in the envelope.
//!
//! Wired via daemon `forward_blob` / auto blob path in `forward_draft` when payload
//! exceeds the inline comfort zone: seal_to_temp → hub upload-url → PUT → envelope.blob_id.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use super::seal::{open, seal};
use super::types::{CryptoError, DevicePubKey, DeviceSecretKey, Envelope};

/// Result of sealing plaintext for blob storage (presigned PUT → set `envelope.blob_id`).
#[derive(Debug)]
pub struct SealedBlob {
    /// Envelope with empty `ciphertext`, wraps, and `sha256` set. `blob_id` filled after hub upload-url.
    pub envelope: Envelope,
    pub ciphertext_path: PathBuf,
    pub sha256_hex: String,
    pub size_bytes: u64,
}

/// Encrypt plaintext, write ciphertext to a temp file, return envelope + sha256 for hub/R2.
pub fn seal_to_temp(plaintext: &[u8], recipients: &[DevicePubKey]) -> Result<SealedBlob, CryptoError> {
    let mut envelope = seal(plaintext, recipients)?;
    let ciphertext = std::mem::take(&mut envelope.ciphertext);
    let sha256_hex = hex::encode(Sha256::digest(&ciphertext));
    envelope.sha256 = Some(sha256_hex.clone());
    envelope.blob_id = None;

    let path = write_temp_ciphertext(&ciphertext)?;
    Ok(SealedBlob {
        envelope,
        ciphertext_path: path,
        sha256_hex,
        size_bytes: ciphertext.len() as u64,
    })
}

/// Decrypt blob ciphertext bytes using envelope wraps + content nonce.
pub fn open_from_bytes(
    envelope: &Envelope,
    ciphertext: &[u8],
    secret: &DeviceSecretKey,
) -> Result<Vec<u8>, CryptoError> {
    if let Some(expected) = envelope.sha256.as_deref() {
        let actual = hex::encode(Sha256::digest(ciphertext));
        if actual != expected {
            return Err(CryptoError::OpenFailed);
        }
    }
    let mut env = envelope.clone();
    env.ciphertext = ciphertext.to_vec();
    open(&env, secret)
}

/// Read ciphertext from path and open.
pub fn open_from_path(
    envelope: &Envelope,
    path: &Path,
    secret: &DeviceSecretKey,
) -> Result<Vec<u8>, CryptoError> {
    let ciphertext = fs::read(path).map_err(|_| CryptoError::OpenFailed)?;
    open_from_bytes(envelope, &ciphertext, secret)
}

/// Attach hub-issued blob id after createUploadUrl.
pub fn with_blob_id(mut envelope: Envelope, blob_id: impl Into<String>) -> Envelope {
    envelope.blob_id = Some(blob_id.into());
    envelope
}

fn write_temp_ciphertext(ciphertext: &[u8]) -> Result<PathBuf, CryptoError> {
    let mut path = std::env::temp_dir();
    path.push(format!("mutande-blob-{}.bin", uuid::Uuid::new_v4()));
    #[cfg(unix)]
    let mut file = {
        use std::os::unix::fs::OpenOptionsExt;
        fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)
            .map_err(|_| CryptoError::OpenFailed)?
    };
    #[cfg(not(unix))]
    let mut file = fs::File::create(&path).map_err(|_| CryptoError::OpenFailed)?;
    file.write_all(ciphertext).map_err(|_| CryptoError::OpenFailed)?;
    file.flush().map_err(|_| CryptoError::OpenFailed)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o600));
    }
    Ok(path)
}

/// Count recipients (kept for call sites that resolve handle → device set before seal).
pub fn recipients_for_blob(recipients: &[DevicePubKey]) -> usize {
    recipients.len()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crypto_box::aead::OsRng;
    use crypto_box::SecretKey;

    fn generate_device_keypair() -> (DevicePubKey, DeviceSecretKey) {
        let sk = SecretKey::generate(&mut OsRng);
        let pk = sk.public_key();
        (
            DevicePubKey(pk.to_bytes()),
            DeviceSecretKey(sk.to_bytes()),
        )
    }

    #[test]
    fn seal_to_temp_roundtrip() {
        let (pk, sk) = generate_device_keypair();
        let msg = b"large handoff artifact";
        let sealed = seal_to_temp(msg, &[pk]).unwrap();
        assert!(sealed.envelope.ciphertext.is_empty());
        assert_eq!(sealed.envelope.sha256.as_deref(), Some(sealed.sha256_hex.as_str()));
        assert!(sealed.envelope.blob_id.is_none());
        assert!(sealed.ciphertext_path.exists());
        assert_eq!(sealed.size_bytes, fs::metadata(&sealed.ciphertext_path).unwrap().len());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(&sealed.ciphertext_path).unwrap().permissions();
            assert_eq!(mode.mode() & 0o777, 0o600);
        }

        let opened = open_from_path(&sealed.envelope, &sealed.ciphertext_path, &sk).unwrap();
        assert_eq!(opened, msg);

        let with_id = with_blob_id(sealed.envelope.clone(), "blob-123");
        assert_eq!(with_id.blob_id.as_deref(), Some("blob-123"));

        let _ = fs::remove_file(&sealed.ciphertext_path);
    }

    #[test]
    fn tampered_blob_sha256_fails() {
        let (pk, sk) = generate_device_keypair();
        let sealed = seal_to_temp(b"secret", &[pk]).unwrap();
        let mut bytes = fs::read(&sealed.ciphertext_path).unwrap();
        bytes[0] ^= 0xff;
        assert_eq!(
            open_from_bytes(&sealed.envelope, &bytes, &sk),
            Err(CryptoError::OpenFailed)
        );
        let _ = fs::remove_file(&sealed.ciphertext_path);
    }
}
