use serde::{Serialize, Deserialize};

use crate::primitives::{Network, PubKey};
use crate::ledger::Ledger;
use crate::event::EventKind;
use crate::slot::SlotLayout;

/// Capsule type (Leaf = 0, Relay = 1)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum CapsuleType {
    Leaf = 0,
    Relay = 1,
}

/// Complete capsule state that can be serialized for FFI.
/// Contains NO logic, only data. Projection from Capsule and Ledger.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CapsuleState {
    /// Capsule public key (32 bytes)
    pub public_key: [u8; 32],

    /// Capsule type: 0 = Leaf, 1 = Relay
    pub capsule_type: u8,

    /// Network: 0 = Hood, 1 = Neste (from primitives.rs)
    pub network: u8,

    /// Slot states: None = empty, Some = StarterId (32 bytes)
    /// Exactly 5 slots as per protocol invariant
    pub slots: [Option<[u8; 32]>; 5],

    /// Current ledger state hash (using last_hash from ledger)
    pub ledger_hash: u64,

    /// Number of active relationships (needs to be computed)
    pub relationships_count: u32,

    /// State version (using events count as version)
    pub version: u32,
}

impl CapsuleState {
    /// Create state projection from capsule and its ledger.
    /// This is a pure function called by Engine, never by Core internally.
    pub fn from_capsule(capsule: &Capsule) -> Self {
        let slot_layout = SlotLayout::from_ledger(&capsule.ledger);
        Self {
            public_key: capsule.pubkey.as_bytes().clone(),
            capsule_type: capsule.capsule_type as u8,
            network: capsule.network as u8,
            slots: slot_layout
                .starter_ids()
                .map(|starter_id| starter_id.map(|id| *id.as_bytes())),
            ledger_hash: capsule.ledger.last_hash(),
            relationships_count: count_relationships(&capsule.ledger),
            version: capsule.ledger.events().len() as u32,
        }
    }
}

/// Capsule struct (composed from primitives)
#[derive(Debug, Clone)]
pub struct Capsule {
    pub pubkey: PubKey,
    pub capsule_type: CapsuleType,
    pub network: Network,
    pub ledger: Ledger,
}

/// Count relationships from ledger
fn count_relationships(ledger: &Ledger) -> u32 {
    let mut established = 0u32;
    let mut broken = 0u32;

    for event in ledger.events() {
        match event.kind() {
            EventKind::RelationshipEstablished => established += 1,
            EventKind::RelationshipBroken => broken += 1,
            _ => {}
        }
    }

    established.saturating_sub(broken)
}


#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::Event;
    use crate::event_payloads::{
        EventPayload, RelationshipBrokenPayload, RelationshipEstablishedPayload,
    };
    use crate::{Signature, StarterId, StarterKind, Timestamp};

    #[test]
    fn test_capsule_state_serialization() {
        let state = CapsuleState {
            public_key: [1; 32],
            capsule_type: 0,
            network: 0,
            slots: [None, None, None, None, None],
            ledger_hash: 42,
            relationships_count: 0,
            version: 1,
        };

        let serialized = bincode::serialize(&state).unwrap();
        let deserialized: CapsuleState = bincode::deserialize(&serialized).unwrap();

        assert_eq!(state, deserialized);
    }

    #[test]
    fn counts_only_active_relationships() {
        let owner = PubKey::from([1u8; 32]);
        let mut ledger = Ledger::new(owner);

        ledger
            .append(Event::new(
                EventKind::RelationshipEstablished,
                RelationshipEstablishedPayload {
                    peer_pubkey: PubKey::from([2u8; 32]),
                    own_starter_id: StarterId::from([3u8; 32]),
                    peer_starter_id: StarterId::from([4u8; 32]),
                    kind: StarterKind::Juice,
                }
                .to_bytes(),
                Timestamp::from(1),
                Signature::from([0u8; 64]),
                owner,
            ))
            .unwrap();

        ledger
            .append(Event::new(
                EventKind::RelationshipBroken,
                RelationshipBrokenPayload {
                    peer_pubkey: PubKey::from([2u8; 32]),
                    own_starter_id: StarterId::from([3u8; 32]),
                }
                .to_bytes(),
                Timestamp::from(2),
                Signature::from([0u8; 64]),
                owner,
            ))
            .unwrap();

        assert_eq!(count_relationships(&ledger), 0);
    }
}
