//! Hivra Engine — Orchestration Layer
//!
//! The Engine is the only orchestration point. It:
//! - Injects dependencies (time, RNG, crypto)
//! - Manages TimeSource, RandomSource
//! - Calls CryptoProvider
//! - Manages transport
//! - Does NOT contain domain invariants

#![no_std]

extern crate alloc;

use core::fmt;

/// Time source trait — provides current timestamp.
///
/// Engine uses this to get time for events.
/// Core never calls this directly.
pub trait TimeSource {
    /// Returns current timestamp in seconds since epoch.
    fn now(&self) -> u64;
}

/// Random source trait — provides cryptographically secure randomness.
///
/// Engine uses this for nonces and invitation IDs.
/// Core never calls this directly.
pub trait RandomSource {
    /// Fills buffer with random bytes.
    fn fill_bytes(&self, buf: &mut [u8]);

    /// Generates a random 32-byte array.
    fn random_32(&self) -> [u8; 32] {
        let mut buf = [0u8; 32];
        self.fill_bytes(&mut buf);
        buf
    }

    /// Generates a random 64-byte array.
    fn random_64(&self) -> [u8; 64] {
        let mut buf = [0u8; 64];
        self.fill_bytes(&mut buf);
        buf
    }
}

/// Crypto provider trait — handles all cryptographic operations.
///
/// Engine uses this to:
/// - Verify signatures
/// - Sign messages
/// - (Optionally) ECDH for encryption
///
/// Core only sees bytes, not crypto algorithms.
pub trait CryptoProvider {
    /// Error type for crypto operations.
    type Error: fmt::Debug;

    /// Verifies a signature.
    ///
    /// # Arguments
    /// * `msg` - The message that was signed
    /// * `pubkey` - Public key (32 bytes)
    /// * `sig` - Signature (64 bytes)
    fn verify(&self, msg: &[u8], pubkey: &[u8; 32], sig: &[u8; 64]) -> Result<(), Self::Error>;

    /// Signs a message.
    ///
    /// # Arguments
    /// * `msg` - Message to sign
    /// * `privkey` - Private key (32 bytes)
    fn sign(&self, msg: &[u8], privkey: &[u8; 32]) -> Result<[u8; 64], Self::Error>;

    /// Optional: ECDH key exchange.
    fn ecdh(&self, privkey: &[u8; 32], pubkey: &[u8; 32]) -> Result<[u8; 32], Self::Error>;
}

/// Secure key store trait — platform-specific secure storage.
///
/// Requirements from spec:
/// - Key is generated on device
/// - Key stored in OS secure storage
/// - Private key never leaves secure storage
/// - Private key never appears in app memory
/// - Private key never crosses FFI boundary
pub trait SecureKeyStore {
    /// Error type for keystore operations.
    type Error: fmt::Debug;

    /// Generates a new key pair in secure storage.
    ///
    /// Returns the public key.
    fn generate(&self) -> Result<[u8; 32], Self::Error>;

    /// Returns the public key of the existing key pair.
    fn public_key(&self) -> Result<[u8; 32], Self::Error>;

    /// Signs a message using the private key in secure storage.
    ///
    /// Private key never leaves secure storage.
    fn sign(&self, msg: &[u8]) -> Result<[u8; 64], Self::Error>;
}

/// Core domain types re-exported from hivra-core.
///
/// Engine works with these types but doesn't modify them directly.
pub use hivra_core::capsule::{Capsule, CapsuleState, CapsuleType};
pub use hivra_core::event_payloads::{
    CapsuleCreatedPayload,
    EventPayload,
    InvitationAcceptedPayload,
    InvitationExpiredPayload,
    InvitationRejectedPayload,
    InvitationSentPayload,
    RejectReason,
    RelationshipBrokenPayload,
    RelationshipEstablishedPayload,
    StarterBurnedPayload,
    StarterCreatedPayload,
};
pub use hivra_core::primitives::SlotIndex;
pub use hivra_core::{
    Event, EventKind, Ledger, Network, PubKey, Signature, Starter, StarterId, StarterKind,
    Timestamp,
};

/// Engine configuration.
#[derive(Debug, Clone)]
pub struct EngineConfig {
    /// Network (Neste or Hood)
    pub network: Network,

    /// Invitation timeout in seconds (default: 24 hours = 86400)
    pub invitation_timeout: u64,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            network: Network::Neste,
            invitation_timeout: 86400, // 24 hours
        }
    }
}

/// The main Engine struct.
///
/// Orchestrates all operations by combining:
/// - Core domain logic
/// - Time source
/// - Random source
/// - Crypto provider
/// - Secure key store
pub struct Engine<T, R, C, K> {
    /// Time source
    time: T,

    /// Random source
    rng: R,

    /// Crypto provider
    crypto: C,

    /// Secure key store
    keystore: K,

    /// Engine configuration
    config: EngineConfig,
}

impl<T, R, C, K> Engine<T, R, C, K>
where
    T: TimeSource,
    R: RandomSource,
    C: CryptoProvider,
    K: SecureKeyStore,
{
    /// Creates a new Engine instance.
    pub fn new(
        time: T,
        rng: R,
        crypto: C,
        keystore: K,
        config: EngineConfig,
    ) -> Self {
        Self {
            time,
            rng,
            crypto,
            keystore,
            config,
        }
    }

    /// Returns current timestamp from time source.
    pub fn now(&self) -> Timestamp {
        Timestamp::from(self.time.now())
    }

    /// Generates random bytes.
    pub fn random_bytes(&self, buf: &mut [u8]) {
        self.rng.fill_bytes(buf);
    }

    /// Generates a random 32-byte ID.
    pub fn random_id(&self) -> [u8; 32] {
        self.rng.random_32()
    }

    /// Returns the current engine configuration.
    pub fn config(&self) -> &EngineConfig {
        &self.config
    }

    /// Returns the public key from secure storage.
    pub fn public_key(&self) -> Result<PubKey, K::Error> {
        self.keystore.public_key().map(PubKey::from)
    }

    /// Signs an event using secure storage.
    ///
    /// This is the only place where signing happens.
    /// Private key never leaves secure storage.
    pub fn sign_event(&self, event: &Event) -> Result<Signature, K::Error> {
        // v3.2 canonical signing bytes are derived deterministically from the event.
        let msg = event.event_id();
        self.keystore.sign(&msg).map(Signature::from)
    }

    /// Verifies an event signature.
    pub fn verify_event(&self, event: &Event, pubkey: &PubKey) -> Result<(), C::Error> {
        let msg = event.event_id();
        self.crypto.verify(&msg, pubkey.as_bytes(), event.signature().as_bytes())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mock time source for testing.
    struct MockTime {
        now: u64,
    }

    impl TimeSource for MockTime {
        fn now(&self) -> u64 {
            self.now
        }
    }

    /// Mock random source for testing.
    struct MockRng {
        fixed: [u8; 32],
    }

    impl RandomSource for MockRng {
        fn fill_bytes(&self, buf: &mut [u8]) {
            for (i, byte) in buf.iter_mut().enumerate() {
                *byte = self.fixed[i % 32];
            }
        }
    }

    /// Mock crypto provider for testing.
    struct MockCrypto;

    impl CryptoProvider for MockCrypto {
        type Error = ();

        fn verify(&self, _msg: &[u8], _pubkey: &[u8; 32], _sig: &[u8; 64]) -> Result<(), Self::Error> {
            Ok(()) // Always succeeds in tests
        }

        fn sign(&self, _msg: &[u8], _privkey: &[u8; 32]) -> Result<[u8; 64], Self::Error> {
            Ok([1; 64]) // Fixed signature
        }

        fn ecdh(&self, _privkey: &[u8; 32], _pubkey: &[u8; 32]) -> Result<[u8; 32], Self::Error> {
            Ok([2; 32]) // Fixed ECDH result for tests
        }
    }

    /// Mock key store for testing.
    struct MockKeyStore {
        pubkey: [u8; 32],
    }

    impl SecureKeyStore for MockKeyStore {
        type Error = ();

        fn generate(&self) -> Result<[u8; 32], Self::Error> {
            Ok(self.pubkey)
        }

        fn public_key(&self) -> Result<[u8; 32], Self::Error> {
            Ok(self.pubkey)
        }

        fn sign(&self, _msg: &[u8]) -> Result<[u8; 64], Self::Error> {
            Ok([2; 64])
        }
    }

    #[test]
    fn test_engine_creation() {
        let time = MockTime { now: 1234567890 };
        let rng = MockRng { fixed: [42; 32] };
        let crypto = MockCrypto;
        let keystore = MockKeyStore { pubkey: [1; 32] };
        let config = EngineConfig::default();

        let engine = Engine::new(time, rng, crypto, keystore, config);

        assert_eq!(engine.now(), Timestamp::from(1234567890));
        assert_eq!(engine.public_key().unwrap(), PubKey::from([1; 32]));
    }

    #[test]
    fn test_random_id() {
        let time = MockTime { now: 0 };
        let rng = MockRng { fixed: [42; 32] };
        let crypto = MockCrypto;
        let keystore = MockKeyStore { pubkey: [1; 32] };
        let config = EngineConfig::default();

        let engine = Engine::new(time, rng, crypto, keystore, config);
        let id = engine.random_id();

        assert_eq!(id, [42; 32]); // From fixed RNG
    }
}
