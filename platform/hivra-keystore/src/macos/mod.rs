//! macOS Keychain implementation.

use crate::{Error, Result, Seed};

const KEYCHAIN_SERVICE: &str = "com.hivra.keystore";
const KEYCHAIN_ACCOUNT: &str = "capsule_seed";

fn entry() -> Result<keyring::Entry> {
    keyring::Entry::new(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT)
        .map_err(|e| Error::PlatformError(e.to_string()))
}

/// Stores the capsule seed in the macOS Keychain.
pub fn store_seed(seed: &Seed) -> Result<()> {
    let encoded = encode_hex(seed.as_bytes());
    entry()?
        .set_password(&encoded)
        .map_err(|e| Error::PlatformError(e.to_string()))
}

/// Loads the capsule seed from the macOS Keychain.
pub fn load_seed() -> Result<Seed> {
    let encoded = entry()?
        .get_password()
        .map_err(|e| map_get_error(e))?;

    let bytes = decode_hex_32(&encoded)?;
    Ok(Seed::new(bytes))
}

/// Deletes the capsule seed from the macOS Keychain.
pub fn delete_seed() -> Result<()> {
    match entry()?
        .delete_credential()
        .map_err(|e| map_get_error(e))
    {
        Ok(()) => Ok(()),
        Err(Error::KeyNotFound) => Ok(()),
        Err(other) => Err(other),
    }
}

/// Returns `true` if a seed entry exists in the macOS Keychain.
pub fn seed_exists() -> bool {
    entry()
        .and_then(|e| e.get_password().map_err(map_get_error))
        .is_ok()
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
