//! Safety numbers for contact verification (Signal-style fingerprint display).

use sha2::{Digest, Sha256};

use super::types::DevicePubKey;

/// QR / compare payload prefix: `mutande:safety:<handle>:<fingerprint>`.
pub const SAFETY_URI_PREFIX: &str = "mutande:safety:";

/// SHA-256 fingerprint of a device pubkey, displayed as 12 groups of 5 decimal digits
/// (60 digits total) — enough for a visual/QR compare without exposing the raw key.
pub fn safety_number(pubkey: &DevicePubKey) -> String {
    let digest = Sha256::digest(pubkey.0);
    let mut groups = Vec::with_capacity(12);
    // Take 30 bytes → 10 u24 chunks; pad with first 6 bytes for 12 groups.
    let mut bytes = [0u8; 36];
    bytes[..32].copy_from_slice(&digest);
    bytes[32..36].copy_from_slice(&digest[..4]);
    for chunk in bytes.chunks_exact(3) {
        let n = ((chunk[0] as u32) << 16) | ((chunk[1] as u32) << 8) | (chunk[2] as u32);
        groups.push(format!("{:05}", n % 100_000));
    }
    groups.join(" ")
}

/// Build a compare/QR payload string for a handle + pubkey.
pub fn safety_uri(handle: &str, pubkey: &DevicePubKey) -> String {
    format!("{SAFETY_URI_PREFIX}{handle}:{}", safety_number(pubkey))
}

/// Parse `mutande:safety:<handle>:<fingerprint>` (fingerprint may contain spaces).
pub fn parse_safety_uri(uri: &str) -> Option<(String, String)> {
    let rest = uri.strip_prefix(SAFETY_URI_PREFIX)?;
    let (handle, fp) = rest.split_once(':')?;
    if handle.is_empty() || fp.is_empty() {
        return None;
    }
    Some((handle.to_string(), fp.to_string()))
}

/// Constant-time-ish compare of two fingerprint strings (ignores whitespace).
pub fn fingerprints_match(a: &str, b: &str) -> bool {
    let na: String = a.chars().filter(|c| !c.is_whitespace()).collect();
    let nb: String = b.chars().filter(|c| !c.is_whitespace()).collect();
    na == nb
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn safety_number_stable_and_grouped() {
        let pk = DevicePubKey([7u8; 32]);
        let a = safety_number(&pk);
        let b = safety_number(&pk);
        assert_eq!(a, b);
        let parts: Vec<_> = a.split_whitespace().collect();
        assert_eq!(parts.len(), 12);
        assert!(parts.iter().all(|p| p.len() == 5 && p.chars().all(|c| c.is_ascii_digit())));
    }

    #[test]
    fn different_keys_differ() {
        let a = safety_number(&DevicePubKey([1u8; 32]));
        let b = safety_number(&DevicePubKey([2u8; 32]));
        assert_ne!(a, b);
    }

    #[test]
    fn uri_roundtrip() {
        let pk = DevicePubKey([9u8; 32]);
        let uri = safety_uri("alice@acme", &pk);
        let (handle, fp) = parse_safety_uri(&uri).unwrap();
        assert_eq!(handle, "alice@acme");
        assert!(fingerprints_match(&fp, &safety_number(&pk)));
    }

    #[test]
    fn fingerprints_match_ignores_spaces() {
        assert!(fingerprints_match("12345 67890", "1234567890"));
        assert!(!fingerprints_match("11111", "22222"));
    }
}
