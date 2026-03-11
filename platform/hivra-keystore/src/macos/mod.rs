//! macOS Keychain implementation.

use crate::{Error, Result, Seed};
use sha2::{Digest, Sha256};

const KEYCHAIN_SERVICE: &str = "com.hivra.keystore";
const LEGACY_KEYCHAIN_ACCOUNT: &str = "capsule_seed";
const ACTIVE_SEED_ACCOUNT: &str = "active_capsule_seed_account";

fn entry_for_account(account: &str) -> Result<keyring::Entry> {
    keyring::Entry::new(KEYCHAIN_SERVICE, account)
        .map_err(|e| Error::PlatformError(e.to_string()))
}

/// Stores the capsule seed in the macOS Keychain.
pub fn store_seed(seed: &Seed) -> Result<()> {
    let encoded = encode_hex(seed.as_bytes());
    let seed_account = seed_account(seed);
    entry_for_account(&seed_account)?
        .set_password(&encoded)
        .map_err(|e| Error::PlatformError(e.to_string()))?;
    entry_for_account(ACTIVE_SEED_ACCOUNT)?
        .set_password(&seed_account)
        .map_err(|e| Error::PlatformError(e.to_string()))
}

/// Loads the capsule seed from the macOS Keychain.
pub fn load_seed() -> Result<Seed> {
    if let Ok(account) = active_seed_account() {
        match load_seed_from_account(&account) {
            Ok(seed) => return Ok(seed),
            Err(Error::KeyNotFound) => {}
            Err(other) => return Err(other),
        }
    }

    // Backward-compatibility for old single-account storage.
    let encoded = entry_for_account(LEGACY_KEYCHAIN_ACCOUNT)?
        .get_password()
        .map_err(map_get_error)?;
    let bytes = decode_hex_32(&encoded)?;
    let seed = Seed::new(bytes);
    // Best-effort migration to namespaced account model.
    let _ = store_seed(&seed);
    Ok(seed)
}

/// Deletes the capsule seed from the macOS Keychain.
pub fn delete_seed() -> Result<()> {
    if let Ok(account) = active_seed_account() {
        delete_account_credential(&account)?;
    }
    delete_account_credential(ACTIVE_SEED_ACCOUNT)?;
    delete_account_credential(LEGACY_KEYCHAIN_ACCOUNT)?;
    Ok(())
}

/// Returns `true` if a seed entry exists in the macOS Keychain.
pub fn seed_exists() -> bool {
    if let Ok(account) = active_seed_account() {
        if load_seed_from_account(&account).is_ok() {
            return true;
        }
    }
    entry_for_account(LEGACY_KEYCHAIN_ACCOUNT)
        .and_then(|e| e.get_password().map_err(map_get_error))
        .is_ok()
}

fn active_seed_account() -> Result<String> {
    entry_for_account(ACTIVE_SEED_ACCOUNT)?
        .get_password()
        .map_err(map_get_error)
}

fn load_seed_from_account(account: &str) -> Result<Seed> {
    let encoded = entry_for_account(account)?
        .get_password()
        .map_err(map_get_error)?;
    let bytes = decode_hex_32(&encoded)?;
    Ok(Seed::new(bytes))
}

fn delete_account_credential(account: &str) -> Result<()> {
    match entry_for_account(account)?
        .delete_credential()
        .map_err(map_get_error)
    {
        Ok(()) | Err(Error::KeyNotFound) => Ok(()),
        Err(other) => Err(other),
    }
}

fn seed_account(seed: &Seed) -> String {
    let mut hasher = Sha256::new();
    hasher.update(seed.as_bytes());
    hasher.update(b"hivra_capsule_seed_account_v1");
    let hash = hasher.finalize();
    format!("capsule_seed:{}", encode_hex(hash.as_slice()))
}

fn map_get_error(err: keyring::Error) -> Error {
    match err {
        keyring::Error::NoEntry => Error::KeyNotFound,
        other => Error::PlatformError(other.to_string()),
    }
}

fn encode_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0x0f) as usize] as char);
    }
    out
}

fn decode_hex_32(input: &str) -> Result<[u8; 32]> {
    if input.len() != 64 {
        return Err(Error::InvalidSeedLength(input.len() / 2));
    }

    let mut out = [0u8; 32];
    let bytes = input.as_bytes();
    for i in 0..32 {
        let hi = from_hex_nibble(bytes[i * 2])
            .ok_or_else(|| Error::PlatformError("Invalid seed encoding in keychain".to_string()))?;
        let lo = from_hex_nibble(bytes[i * 2 + 1])
            .ok_or_else(|| Error::PlatformError("Invalid seed encoding in keychain".to_string()))?;
        out[i] = (hi << 4) | lo;
    }
    Ok(out)
}

fn from_hex_nibble(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(c - b'a' + 10),
        b'A'..=b'F' => Some(c - b'A' + 10),
        _ => None,
    }
}
