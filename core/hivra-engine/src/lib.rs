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

use alloc::vec;
use alloc::vec::Vec;
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EngineError<E> {
    Keystore(E),
    MatchingInvitationNotFound,
    NoMatchingStarter,
    NoEmptySlot,
    InvalidAcceptPlan,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreparedEvent {
    pub event: Event,
    pub recipient: Option<PubKey>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IncomingEffect {
    Append(Event),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutgoingRejectionEffect {
    BurnStarter { starter_id: StarterId },
    UnlockOnly,
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

    pub fn prepare_invitation_sent(
        &self,
        starter_id: StarterId,
        to_pubkey: PubKey,
    ) -> Result<PreparedEvent, EngineError<K::Error>> {
        let payload = InvitationSentPayload {
            invitation_id: self.random_id(),
            starter_id,
            to_pubkey,
        };

        self.prepare_event(EventKind::InvitationSent, payload.to_bytes(), Some(to_pubkey))
    }

    pub fn prepare_invitation_accepted(
        &self,
        invitation_id: [u8; 32],
        from_pubkey: PubKey,
        created_starter_id: StarterId,
    ) -> Result<PreparedEvent, EngineError<K::Error>> {
        let payload = InvitationAcceptedPayload {
            invitation_id,
            from_pubkey,
            created_starter_id,
        };

        self.prepare_event(
            EventKind::InvitationAccepted,
            payload.to_bytes(),
            Some(from_pubkey),
        )
    }

    pub fn prepare_invitation_rejected(
        &self,
        invitation_id: [u8; 32],
        to_pubkey: PubKey,
        reason: RejectReason,
    ) -> Result<PreparedEvent, EngineError<K::Error>> {
        let payload = InvitationRejectedPayload {
            invitation_id,
            reason,
        };

        self.prepare_event(
            EventKind::InvitationRejected,
            payload.to_bytes(),
            Some(to_pubkey),
        )
    }

    pub fn prepare_invitation_expired(
        &self,
        invitation_id: [u8; 32],
    ) -> Result<PreparedEvent, EngineError<K::Error>> {
        let payload = InvitationExpiredPayload { invitation_id };
        self.prepare_event(EventKind::InvitationExpired, payload.to_bytes(), None)
    }

    pub fn prepare_starter_created(
        &self,
        starter_id: StarterId,
        nonce: [u8; 32],
        kind: StarterKind,
        network: Network,
    ) -> Result<PreparedEvent, EngineError<K::Error>> {
        let payload = StarterCreatedPayload {
            starter_id,
            nonce,
            kind,
            network: network.to_byte(),
        };
        self.prepare_event(EventKind::StarterCreated, payload.to_bytes(), None)
    }

    pub fn prepare_starter_burned(
        &self,
        starter_id: StarterId,
        reason: u8,
    ) -> Result<PreparedEvent, EngineError<K::Error>> {
        let payload = StarterBurnedPayload { starter_id, reason };
        self.prepare_event(EventKind::StarterBurned, payload.to_bytes(), None)
    }

    pub fn prepare_relationship_established(
        &self,
        peer_pubkey: PubKey,
        own_starter_id: StarterId,
        peer_starter_id: StarterId,
        kind: StarterKind,
    ) -> Result<PreparedEvent, EngineError<K::Error>> {
        let payload = RelationshipEstablishedPayload {
            peer_pubkey,
            own_starter_id,
            peer_starter_id,
            kind,
        };
        self.prepare_event(
            EventKind::RelationshipEstablished,
            payload.to_bytes(),
            None,
        )
    }

    pub fn resolve_accept_plan(
        &self,
        ledger: &Ledger,
        invitation_id: [u8; 32],
    ) -> Result<hivra_core::AcceptPlan, EngineError<K::Error>> {
        let invitation = hivra_core::find_invitation(ledger, invitation_id)
            .ok_or(EngineError::MatchingInvitationNotFound)?;
        let slots = hivra_core::slot::SlotLayout::from_ledger(ledger);
        let kind = self
            .starter_kind_for_id(ledger, invitation.starter_id)
            .ok_or(EngineError::MatchingInvitationNotFound)?;

        Ok(hivra_core::plan_accept_for_kind(ledger, &slots, kind))
    }

    pub fn effects_for_incoming_accept(
        &self,
        ledger: &Ledger,
        accepter_pubkey: PubKey,
        payload: &InvitationAcceptedPayload,
    ) -> Result<Vec<IncomingEffect>, EngineError<K::Error>> {
        let invitation = hivra_core::find_invitation(ledger, payload.invitation_id)
            .ok_or(EngineError::MatchingInvitationNotFound)?;
        let kind = self
            .starter_kind_for_id(ledger, invitation.starter_id)
            .ok_or(EngineError::MatchingInvitationNotFound)?;

        let relationship = self.prepare_relationship_established(
            accepter_pubkey,
            invitation.starter_id,
            payload.created_starter_id,
            kind,
        )?;

        Ok(vec![IncomingEffect::Append(relationship.event)])
    }

    pub fn effects_for_incoming_reject(
        &self,
        ledger: &Ledger,
        payload: &InvitationRejectedPayload,
    ) -> Result<OutgoingRejectionEffect, EngineError<K::Error>> {
        let invitation = hivra_core::find_invitation(ledger, payload.invitation_id)
            .ok_or(EngineError::MatchingInvitationNotFound)?;

        Ok(match payload.reason {
            RejectReason::EmptySlot => OutgoingRejectionEffect::BurnStarter {
                starter_id: invitation.starter_id,
            },
            RejectReason::Other => OutgoingRejectionEffect::UnlockOnly,
        })
    }

    fn prepare_event(
        &self,
        kind: EventKind,
        payload: Vec<u8>,
        recipient: Option<PubKey>,
    ) -> Result<PreparedEvent, EngineError<K::Error>> {
        let signer = self.public_key().map_err(EngineError::Keystore)?;
        let timestamp = self.now();
        let unsigned = Event::new(
            kind,
            payload,
            timestamp,
            Signature::from([0u8; 64]),
            signer,
        );
        let signature = self.sign_event(&unsigned).map_err(EngineError::Keystore)?;
        let event = Event::new(
            kind,
            unsigned.payload().to_vec(),
            timestamp,
            signature,
            signer,
        );

        Ok(PreparedEvent { event, recipient })
    }

    fn starter_kind_for_id(&self, ledger: &Ledger, starter_id: StarterId) -> Option<StarterKind> {
        for event in ledger.events() {
            if event.kind() != EventKind::StarterCreated {
                continue;
            }

            let Ok(payload) = StarterCreatedPayload::from_bytes(event.payload()) else {
                continue;
            };

            if payload.starter_id == starter_id {
                return Some(payload.kind);
            }
        }

        None
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

    #[test]
    fn prepare_invitation_sent_creates_signed_event_and_recipient() {
        let time = MockTime { now: 7 };
        let rng = MockRng { fixed: [42; 32] };
        let crypto = MockCrypto;
        let keystore = MockKeyStore { pubkey: [1; 32] };
        let engine = Engine::new(time, rng, crypto, keystore, EngineConfig::default());

        let prepared = engine
            .prepare_invitation_sent(StarterId::from([9; 32]), PubKey::from([2; 32]))
            .unwrap();

        assert_eq!(prepared.event.kind(), EventKind::InvitationSent);
        assert_eq!(prepared.event.timestamp(), Timestamp::from(7));
        assert_eq!(prepared.event.signer(), &PubKey::from([1; 32]));
        assert_eq!(prepared.recipient, Some(PubKey::from([2; 32])));

        let payload = InvitationSentPayload::from_bytes(prepared.event.payload()).unwrap();
        assert_eq!(payload.invitation_id, [42; 32]);
        assert_eq!(payload.starter_id, StarterId::from([9; 32]));
        assert_eq!(payload.to_pubkey, PubKey::from([2; 32]));
    }

    #[test]
    fn resolve_accept_plan_uses_core_projection() {
        let time = MockTime { now: 0 };
        let rng = MockRng { fixed: [42; 32] };
        let crypto = MockCrypto;
        let keystore = MockKeyStore { pubkey: [1; 32] };
        let engine = Engine::new(time, rng, crypto, keystore, EngineConfig::default());
        let owner = PubKey::from([1; 32]);
        let mut ledger = Ledger::new(owner);

        ledger
            .append(Event::new(
                EventKind::StarterCreated,
                StarterCreatedPayload {
                    starter_id: StarterId::from([4; 32]),
                    nonce: [5; 32],
                    kind: StarterKind::Seed,
                    network: Network::Neste.to_byte(),
                }
                .to_bytes(),
                Timestamp::from(1),
                Signature::from([0; 64]),
                owner,
            ))
            .unwrap();

        ledger
            .append(Event::new(
                EventKind::InvitationSent,
                InvitationSentPayload {
                    invitation_id: [8; 32],
                    starter_id: StarterId::from([4; 32]),
                    to_pubkey: PubKey::from([9; 32]),
                }
                .to_bytes(),
                Timestamp::from(2),
                Signature::from([0; 64]),
                owner,
            ))
            .unwrap();

        let plan = engine.resolve_accept_plan(&ledger, [8; 32]).unwrap();
        assert_eq!(
            plan,
            hivra_core::AcceptPlan::UseExistingStarter {
                relationship_starter_id: StarterId::from([4; 32]),
                created_starter: Some(hivra_core::PlannedStarterCreation {
                    slot: SlotIndex::new(1).unwrap(),
                    kind: StarterKind::Juice,
                }),
            }
        );
    }

    #[test]
    fn incoming_accept_projects_relationship_for_sender() {
        let time = MockTime { now: 11 };
        let rng = MockRng { fixed: [42; 32] };
        let crypto = MockCrypto;
        let keystore = MockKeyStore { pubkey: [1; 32] };
        let engine = Engine::new(time, rng, crypto, keystore, EngineConfig::default());
        let owner = PubKey::from([1; 32]);
        let mut ledger = Ledger::new(owner);

        ledger
            .append(Event::new(
                EventKind::StarterCreated,
                StarterCreatedPayload {
                    starter_id: StarterId::from([3; 32]),
                    nonce: [4; 32],
                    kind: StarterKind::Juice,
                    network: Network::Neste.to_byte(),
                }
                .to_bytes(),
                Timestamp::from(1),
                Signature::from([0; 64]),
                owner,
            ))
            .unwrap();

        ledger
            .append(Event::new(
                EventKind::InvitationSent,
                InvitationSentPayload {
                    invitation_id: [7; 32],
                    starter_id: StarterId::from([3; 32]),
                    to_pubkey: PubKey::from([2; 32]),
                }
                .to_bytes(),
                Timestamp::from(2),
                Signature::from([0; 64]),
                owner,
            ))
            .unwrap();

        let effects = engine
            .effects_for_incoming_accept(
                &ledger,
                PubKey::from([2; 32]),
                &InvitationAcceptedPayload {
                    invitation_id: [7; 32],
                    from_pubkey: PubKey::from([1; 32]),
                    created_starter_id: StarterId::from([6; 32]),
                },
            )
            .unwrap();

        assert_eq!(effects.len(), 1);
        let IncomingEffect::Append(event) = &effects[0];
        assert_eq!(event.kind(), EventKind::RelationshipEstablished);
        let payload = RelationshipEstablishedPayload::from_bytes(event.payload()).unwrap();
        assert_eq!(payload.peer_pubkey, PubKey::from([2; 32]));
        assert_eq!(payload.own_starter_id, StarterId::from([3; 32]));
        assert_eq!(payload.peer_starter_id, StarterId::from([6; 32]));
        assert_eq!(payload.kind, StarterKind::Juice);
    }

    #[test]
    fn incoming_empty_slot_reject_requires_sender_burn() {
        let time = MockTime { now: 0 };
        let rng = MockRng { fixed: [42; 32] };
        let crypto = MockCrypto;
        let keystore = MockKeyStore { pubkey: [1; 32] };
        let engine = Engine::new(time, rng, crypto, keystore, EngineConfig::default());
        let owner = PubKey::from([1; 32]);
        let mut ledger = Ledger::new(owner);

        ledger
            .append(Event::new(
                EventKind::InvitationSent,
                InvitationSentPayload {
                    invitation_id: [7; 32],
                    starter_id: StarterId::from([3; 32]),
                    to_pubkey: PubKey::from([2; 32]),
                }
                .to_bytes(),
                Timestamp::from(2),
                Signature::from([0; 64]),
                owner,
            ))
            .unwrap();

        let effect = engine
            .effects_for_incoming_reject(
                &ledger,
                &InvitationRejectedPayload {
                    invitation_id: [7; 32],
                    reason: RejectReason::EmptySlot,
                },
            )
            .unwrap();

        assert_eq!(
            effect,
            OutgoingRejectionEffect::BurnStarter {
                starter_id: StarterId::from([3; 32]),
            }
        );
    }
}
