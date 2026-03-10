//! Event types for Hivra Core

use crate::{PubKey, Signature, Timestamp};
use alloc::vec::Vec;
use serde::{Serialize, Deserialize};
use sha2::{Digest, Sha256};

/// Protocol version
pub const PROTOCOL_VERSION: u8 = 3;

/// Kind of event
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum EventKind {
    CapsuleCreated = 0,
    InvitationSent = 1,
    InvitationAccepted = 2,
    InvitationRejected = 3,
    InvitationExpired = 4,
    StarterCreated = 5,
    StarterBurned = 6,
    RelationshipEstablished = 7,
    RelationshipBroken = 8,
}

/// A signed event
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Event {
    version: u8,
    kind: EventKind,
    payload: Vec<u8>,
    timestamp: Timestamp,
    signature: Signature,
    signer: PubKey,
}

impl Event {
    pub fn new(
        kind: EventKind,
        payload: Vec<u8>,
        timestamp: Timestamp,
        signature: Signature,
        signer: PubKey,
    ) -> Self {
        Self {
            version: PROTOCOL_VERSION,
            kind,
            payload,
            timestamp,
            signature,
            signer,
        }
    }

    pub fn version(&self) -> u8 { self.version }
    pub fn kind(&self) -> EventKind { self.kind }
    pub fn payload(&self) -> &[u8] { &self.payload }
    pub fn timestamp(&self) -> Timestamp { self.timestamp }
    pub fn signature(&self) -> &Signature { &self.signature }
    pub fn signer(&self) -> &PubKey { &self.signer }

    /// Deterministic event ID from protocol fields.
    ///
    /// v3.2 formula:
    /// SHA256(version || kind || payload_bytes)
    pub fn event_id(&self) -> [u8; 32] {
        let mut hasher = Sha256::new();
        hasher.update([self.version]);
        hasher.update([self.kind as u8]);
        hasher.update(&self.payload);
        let digest = hasher.finalize();

        let mut out = [0u8; 32];
        out.copy_from_slice(&digest);
        out
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec;

    #[test]
    fn test_event_id_deterministic() {
        let event = Event::new(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(123),
            Signature::from([9u8; 64]),
            PubKey::from([7u8; 32]),
        );

        let id1 = event.event_id();
        let id2 = event.event_id();
        assert_eq!(id1, id2);
    }

    #[test]
    fn test_event_id_ignores_timestamp_signature_and_signer() {
        let event_a = Event::new(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(100),
            Signature::from([1u8; 64]),
            PubKey::from([2u8; 32]),
        );
        let event_b = Event::new(
            EventKind::InvitationSent,
            vec![1, 2, 3],
            Timestamp::from(200),
            Signature::from([3u8; 64]),
            PubKey::from([4u8; 32]),
        );

        assert_eq!(event_a.event_id(), event_b.event_id());
    }
}

