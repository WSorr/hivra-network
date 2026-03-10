//! Hivra Keystore
//! Platform-specific secure storage for cryptographic keys.

#![warn(missing_docs)]

use std::fmt;
use zeroize::Zeroize;

/// Errors that can occur in keystore operations
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// Platform-specific keychain error
    #[error("Platform keystore error: {0}")]
    PlatformError(String),
    /// Key not found in keystore
    #[error("Key not found")]
    KeyNotFound,
    /// Invalid seed length
    #[error("Invalid seed length: {0}, expected 32")]
    InvalidSeedLength(usize),
    /// BIP39 mnemonic error
    #[error("BIP39 error: {0}")]
    Bip39Error(String),
    /// Signature error
    #[error("Signature error: {0}")]
    SignatureError(String),
    /// I/O error
    #[error("I/O error: {0}")]
    IoError(#[from] std::io::Error),
}

/// Result type for keystore operations
pub type Result<T> = std::result::Result<T, Error>;

/// A 32-byte seed for deterministic key generation
#[derive(Clone, Zeroize)]
#[zeroize(drop)]
pub struct Seed(pub [u8; 32]);

impl Seed {
    /// Create a new seed from bytes
    pub fn new(bytes: [u8; 32]) -> Self { Self(bytes) }
    /// Get seed as bytes
    pub fn as_bytes(&self) -> &[u8; 32] { &self.0 }
}

impl fmt::Debug for Seed {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Seed").field("bytes", &"[redacted]").finish()
    }
}

/// Convert seed to BIP39 mnemonic phrase
pub fn seed_to_mnemonic(seed: &Seed, word_count: usize) -> Result<String> {
    use bip39::{Mnemonic, Language};
    let entropy = match word_count {
        12 => &seed.0[..16],
        24 => &seed.0[..32],
        _ => return Err(Error::Bip39Error("Word count must be 12 or 24".to_string())),
    };
    let mnemonic = Mnemonic::from_entropy_in(Language::English, entropy)
        .map_err(|e| Error::Bip39Error(e.to_string()))?;
    Ok(mnemonic.to_string())
}

/// Convert BIP39 mnemonic phrase to seed
pub fn mnemonic_to_seed(phrase: &str) -> Result<Seed> {
    use bip39::{Mnemonic, Language};
    let mnemonic = Mnemonic::parse_in(Language::English, phrase)
        .map_err(|e| Error::Bip39Error(e.to_string()))?;
    let entropy = mnemonic.to_entropy();
    let mut seed_bytes = [0u8; 32];
    let len = entropy.len().min(32);
    seed_bytes[..len].copy_from_slice(&entropy);
    Ok(Seed(seed_bytes))
}

/// Derive Nostr keypair from seed using HKDF
pub fn derive_nostr_keypair(seed: &Seed) -> Result<[u8; 32]> {
    use hkdf::Hkdf;
    use sha2::Sha256;
    let info = b"HIVRA_NOSTR_KEY_v1";
    let hk = Hkdf::<Sha256>::new(None, seed.as_bytes());
    let mut okm = [0u8; 32];
    hk.expand(info, &mut okm)
        .map_err(|_| Error::Bip39Error("HKDF expansion failed".to_string()))?;
    Ok(okm)
}

#[cfg(target_os = "macos")]
pub mod macos;

// Re-export platform functions at the crate root for convenience
#[cfg(target_os = "macos")]
pub use macos::{store_seed, load_seed, delete_seed, seed_exists};

#[cfg(target_os = "android")]
pub mod android;

#[cfg(target_os = "android")]
pub use android::{store_seed, load_seed, delete_seed, seed_exists};
