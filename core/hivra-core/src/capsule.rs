use serde::{Serialize, Deserialize};

use crate::primitives::{Network, PubKey};
use crate::ledger::Ledger;
use crate::event::EventKind;
use crate::event_payloads::{EventPayload, StarterBurnedPayload, StarterCreatedPayload};

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
        Self {
            public_key: capsule.pubkey.as_bytes().clone(),
            capsule_type: capsule.capsule_type as u8,
            network: capsule.network as u8,
            slots: extract_slots_from_ledger(&capsule.ledger),
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

/// Helper to extract slot states from ledger.
/// Slots are computed by scanning ledger events, never stored directly.
fn extract_slots_from_ledger(ledger: &Ledger) -> [Option<[u8; 32]>; 5] {
    let mut slots = [None, None, None, None, None];
    
    // Iterate through ledger events in order
    for event in ledger.events() {
        match event.kind() {
            EventKind::StarterCreated => {
                if let Ok(payload) = StarterCreatedPayload::from_bytes(event.payload()) {
                    if let Some(slot_idx) = find_free_slot(&slots) {
                        slots[slot_idx] = Some(*payload.starter_id.as_bytes());
                    }
                }
            }
            EventKind::StarterBurned => {
                if let Ok(payload) = StarterBurnedPayload::from_bytes(event.payload()) {
                    let starter_id = *payload.starter_id.as_bytes();
                    // Remove starter from its slot
                    for slot in slots.iter_mut() {
                        if *slot == Some(starter_id) {
                            *slot = None;
                            break;
                        }
                    }
                }
            }
            // Other events don't affect slots directly
            _ => {}
        }
    }
    
    slots
}

/// Count relationships from ledger
fn count_relationships(ledger: &Ledger) -> u32 {
    let mut count = 0;
    for event in ledger.events() {
        if let EventKind::RelationshipEstablished = event.kind() {
            count += 1;
        }
    }
    count
}

/// Find first free slot
fn find_free_slot(slots: &[Option<[u8; 32]>; 5]) -> Option<usize> {
    slots.iter().position(|slot| slot.is_none())
}


#[cfg(test)]
mod tests {
    use super::*;

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
}
