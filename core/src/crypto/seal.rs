use std::collections::HashSet;

use chacha20poly1305::aead::{Aead, KeyInit};
use chacha20poly1305::{ChaCha20Poly1305, Nonce as ContentNonce};
use crypto_box::aead::OsRng;
use crypto_box::{ChaChaBox, Nonce as BoxNonce, PublicKey, SecretKey};
use rand::RngCore;

use super::types::{CryptoError, DevicePubKey, DeviceSecretKey, Envelope, Wrap};

const ENVELOPE_VERSION: u8 = 1;
const CEK_LEN: usize = 32;
const BOX_NONCE_LEN: usize = 24;

/// Encrypt once; wrap the content key for each recipient device pubkey.
pub fn seal(plaintext: &[u8], recipients: &[DevicePubKey]) -> Result<Envelope, CryptoError> {
    if plaintext.is_empty() {
        return Err(CryptoError::EmptyPlaintext);
    }
    if recipients.is_empty() {
        return Err(CryptoError::EmptyRecipients);
    }

    let mut seen = HashSet::with_capacity(recipients.len());
    for key in recipients {
        if !seen.insert(*key) {
            return Err(CryptoError::DuplicateRecipient);
        }
    }

    let mut rng = OsRng;
    let mut cek = [0u8; CEK_LEN];
    rng.fill_bytes(&mut cek);

    let mut content_nonce = [0u8; 12];
    rng.fill_bytes(&mut content_nonce);

    let cipher = ChaCha20Poly1305::new((&cek).into());
    let ciphertext = cipher
        .encrypt(ContentNonce::from_slice(&content_nonce), plaintext)
        .map_err(|_| CryptoError::OpenFailed)?;

    let mut wraps = Vec::with_capacity(recipients.len());
    for recipient in recipients {
        let ephemeral_secret = SecretKey::generate(&mut rng);
        let ephemeral_public = ephemeral_secret.public_key();
        let recipient_public = public_key_from_device(recipient);
        let mut nonce_bytes = [0u8; BOX_NONCE_LEN];
        rng.fill_bytes(&mut nonce_bytes);
        let nonce = BoxNonce::from_slice(&nonce_bytes);
        let boxed = ChaChaBox::new(&recipient_public, &ephemeral_secret)
            .encrypt(nonce, cek.as_slice())
            .map_err(|_| CryptoError::OpenFailed)?;
        let mut boxed_cek = nonce_bytes.to_vec();
        boxed_cek.extend_from_slice(&boxed);

        wraps.push(Wrap {
            recipient: *recipient,
            ephemeral_public: device_pubkey_from_public(&ephemeral_public),
            boxed_cek,
        });
    }

    Ok(Envelope {
        version: ENVELOPE_VERSION,
        content_nonce,
        ciphertext,
        wraps,
        blob_id: None,
        sha256: None,
    })
}

/// Open an envelope with the local device secret key.
pub fn open(envelope: &Envelope, secret: &DeviceSecretKey) -> Result<Vec<u8>, CryptoError> {
    if envelope.version != ENVELOPE_VERSION {
        return Err(CryptoError::OpenFailed);
    }

    let own_public = device_pubkey_from_secret(secret);
    let wrap = envelope
        .wraps
        .iter()
        .find(|w| w.recipient == own_public)
        .ok_or(CryptoError::NoWrapForSelf)?;

    let recipient_secret = secret_key_from_device(secret);
    let ephemeral_public = public_key_from_device(&wrap.ephemeral_public);

    if wrap.boxed_cek.len() < BOX_NONCE_LEN {
        return Err(CryptoError::OpenFailed);
    }
    let (nonce_bytes, boxed) = wrap.boxed_cek.split_at(BOX_NONCE_LEN);
    let nonce = BoxNonce::from_slice(nonce_bytes);

    let cek_bytes = ChaChaBox::new(&ephemeral_public, &recipient_secret)
        .decrypt(nonce, boxed)
        .map_err(|_| CryptoError::OpenFailed)?;

    if cek_bytes.len() != CEK_LEN {
        return Err(CryptoError::OpenFailed);
    }
    let mut cek = [0u8; CEK_LEN];
    cek.copy_from_slice(&cek_bytes);

    let cipher = ChaCha20Poly1305::new((&cek).into());
    cipher
        .decrypt(ContentNonce::from_slice(&envelope.content_nonce), envelope.ciphertext.as_slice())
        .map_err(|_| CryptoError::OpenFailed)
}

pub fn device_public_from_secret(secret: &DeviceSecretKey) -> DevicePubKey {
    device_pubkey_from_secret(secret)
}

fn public_key_from_device(key: &DevicePubKey) -> PublicKey {
    PublicKey::from_bytes(key.0)
}

fn secret_key_from_device(key: &DeviceSecretKey) -> SecretKey {
    SecretKey::from_bytes(key.0)
}

fn device_pubkey_from_public(public: &PublicKey) -> DevicePubKey {
    DevicePubKey(public.to_bytes())
}

fn device_pubkey_from_secret(secret: &DeviceSecretKey) -> DevicePubKey {
    let sk = secret_key_from_device(secret);
    device_pubkey_from_public(&sk.public_key())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crypto_box::aead::OsRng as BoxOsRng;

    fn generate_device_keypair() -> (DevicePubKey, DeviceSecretKey) {
        let sk = SecretKey::generate(&mut BoxOsRng);
        let pk = sk.public_key();
        (
            DevicePubKey(pk.to_bytes()),
            DeviceSecretKey(sk.to_bytes()),
        )
    }

    #[test]
    fn roundtrip_single_recipient() {
        let (pk, sk) = generate_device_keypair();
        let msg = b"handoff bundle for alice";
        let env = seal(msg, &[pk]).unwrap();
        assert_eq!(env.wraps.len(), 1);
        assert_eq!(open(&env, &sk).unwrap(), msg);
    }

    #[test]
    fn roundtrip_multi_recipient() {
        let (pk_a, sk_a) = generate_device_keypair();
        let (pk_b, sk_b) = generate_device_keypair();
        let msg = b"broadcast @all handoff";
        let env = seal(msg, &[pk_a, pk_b]).unwrap();
        assert_eq!(env.wraps.len(), 2);
        assert_eq!(open(&env, &sk_a).unwrap(), msg);
        assert_eq!(open(&env, &sk_b).unwrap(), msg);
    }

    #[test]
    fn one_ciphertext_many_wraps() {
        let (pk_a, sk_a) = generate_device_keypair();
        let (pk_b, sk_b) = generate_device_keypair();
        let env = seal(b"same content", &[pk_a, pk_b]).unwrap();
        assert_eq!(env.wraps.len(), 2);
        assert!(!env.ciphertext.is_empty());
        assert_eq!(open(&env, &sk_a).unwrap(), b"same content");
        assert_eq!(open(&env, &sk_b).unwrap(), b"same content");
    }

    #[test]
    fn wrong_key_fails_opaque() {
        let (pk, _) = generate_device_keypair();
        let (_, sk_other) = generate_device_keypair();
        let env = seal(b"secret", &[pk]).unwrap();
        assert_eq!(open(&env, &sk_other), Err(CryptoError::NoWrapForSelf));
    }

    #[test]
    fn tamper_fails() {
        let (pk, sk) = generate_device_keypair();
        let mut env = seal(b"secret", &[pk]).unwrap();
        if let Some(b) = env.ciphertext.first_mut() {
            *b ^= 0xff;
        }
        assert_eq!(open(&env, &sk), Err(CryptoError::OpenFailed));
    }

    #[test]
    fn rejects_empty_recipients() {
        assert_eq!(
            seal(b"x", &[]),
            Err(CryptoError::EmptyRecipients)
        );
    }

    #[test]
    fn rejects_duplicate_recipient() {
        let (pk, _) = generate_device_keypair();
        assert_eq!(
            seal(b"x", &[pk, pk]),
            Err(CryptoError::DuplicateRecipient)
        );
    }
}
