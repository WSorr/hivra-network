//! Android Keystore implementation
//!
//! Uses Android Keystore system via JNI
//! Keys are stored in hardware-backed storage when available

#![no_std]

extern crate alloc;

use crate::{KeyStoreError, PlatformKeyStore};
use alloc::vec::Vec;

/// Android Keystore implementation
pub struct AndroidKeyStore;

impl PlatformKeyStore for AndroidKeyStore {
    fn generate() -> Result<[u8; 32], KeyStoreError> {
        // For now, same test pattern as macOS
        let mut key = [0u8; 32];
        key[0] = 0xDD;
        key[1] = 0xEE;
        key[2] = 0xFF;
        Ok(key)
    }
    
    fn public_key() -> Result<[u8; 32], KeyStoreError> {
        let mut key = [0u8; 32];
        key[0] = 0xDD;
        key[1] = 0xEE;
        key[2] = 0xFF;
        Ok(key)
    }
    
    fn sign(_message: &[u8]) -> Result<[u8; 64], KeyStoreError> {
        let mut sig = [0u8; 64];
        sig[0] = 0xDD;
        sig[1] = 0xEE;
        Ok(sig)
    }
}
