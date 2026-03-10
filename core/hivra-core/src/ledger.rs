//! Ledger — append-only journal of signed events.

use crate::{Event, EventKind, PubKey, Timestamp, PROTOCOL_VERSION};
use alloc::vec::Vec;
use core::hash::{Hash, Hasher};
use serde::{Serialize, Deserialize};

/// Error type for ledger operations
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LedgerError {
    InvalidSignature,
    InvalidOrder,
    WrongVersion,
    DuplicateEvent,
}

/// Simple hasher for no_std compatibility
#[derive(Default)]
struct SimpleHasher(u64);

impl SimpleHasher {
    fn new() -> Self { Self(0) }
    fn finish(&self) -> u64 { self.0 }
}

impl Hasher for SimpleHasher {
    fn write(&mut self, bytes: &[u8]) {
        for b in bytes {
            self.0 = self.0.wrapping_mul(0x9e3779b97f4a7c15);
            self.0 ^= *b as u64;
        }
    }
    fn finish(&self) -> u64 { self.0 }
}

/// Ledger — append-only journal of signed events
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Ledger {
    events: Vec<Event>,
    owner: PubKey,
    last_hash: u64,
}

impl Ledger {
    pub fn new(owner: PubKey) -> Self {
        Self { events: Vec::new(), owner, last_hash: 0 }
    }

    pub fn owner(&self) -> &PubKey { &self.owner }
    pub fn events(&self) -> &[Event] { &self.events }
    pub fn last_hash(&self) -> u64 { self.last_hash }

    pub fn append(&mut self, event: Event) -> Result<(), LedgerError> {
        if event.version() != PROTOCOL_VERSION {
            return Err(LedgerError::WrongVersion);
        }

        if event.signer() != &self.owner {
            return Err(LedgerError::InvalidSignature);
        }

        if self.events.iter().any(|existing| existing == &event) {
            return Err(LedgerError::DuplicateEvent);
        }

        if let Some(last) = self.events.last() {
            if event.timestamp() < last.timestamp() {
                return Err(LedgerError::InvalidOrder);
            }
        }

        let mut hasher = SimpleHasher::new();
        self.last_hash.hash(&mut hasher);
        event.hash(&mut hasher);
        self.last_hash = hasher.finish();

        self.events.push(event);
        Ok(())
    }

    pub fn events_in_range(&self, from: Timestamp, to: Timestamp) -> Vec<&Event> {
        self.events
            .iter()
            .filter(|e| e.timestamp() >= from && e.timestamp() <= to)
            .collect()
    }

    pub fn events_of_kind(&self, kind: EventKind) -> Vec<&Event> {
        self.events
            .iter()
            .filter(|e| e.kind() == kind)
            .collect()
    }

    pub fn verify(&self) -> bool {
        let mut hash = 0u64;
        let mut last_ts = None;

        for (index, event) in self.events.iter().enumerate() {
            if event.version() != PROTOCOL_VERSION {
                return false;
            }

            if event.signer() != &self.owner {
                return false;
            }

            if self.events[..index].iter().any(|existing| existing == event) {
                return false;
            }

            if let Some(ts) = last_ts {
                if event.timestamp() < ts {
                    return false;
                }
            }
            last_ts = Some(event.timestamp());

            let mut hasher = SimpleHasher::new();
            hash.hash(&mut hasher);
            event.hash(&mut hasher);
            hash = hasher.finish();
        }

        hash == self.last_hash
    }
}

impl Hash for Event {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.kind().hash(state);
        self.payload().hash(state);
        self.timestamp().hash(state);
        self.signature().as_bytes().hash(state);
        self.signer().as_bytes().hash(state);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{EventKind, Signature, Timestamp};
    use alloc::vec;

    #[test]
    fn test_ledger_append() {
        let owner = PubKey::from([1u8; 32]);
        let mut ledger = Ledger::new(owner);

        let event = Event::new(
            EventKind::CapsuleCreated,
            vec![0, 1],
            Timestamp::from(1000),
            Signature::from([0u8; 64]),
            owner,
        );

        assert!(ledger.append(event).is_ok());
        assert_eq!(ledger.events().len(), 1);
    }

    #[test]
    fn test_ledger_rejects_duplicate_event() {
        let owner = PubKey::from([1u8; 32]);
        let mut ledger = Ledger::new(owner);

        let event = Event::new(
            EventKind::CapsuleCreated,
            vec![0, 1],
            Timestamp::from(1000),
            Signature::from([0u8; 64]),
            owner,
        );

        assert!(ledger.append(event.clone()).is_ok());
        assert_eq!(ledger.append(event), Err(LedgerError::DuplicateEvent));
    }

    #[test]
    fn test_ledger_verify_after_append() {
        let owner = PubKey::from([1u8; 32]);
        let mut ledger = Ledger::new(owner);

        let event = Event::new(
            EventKind::CapsuleCreated,
            vec![0, 1],
            Timestamp::from(1000),
            Signature::from([0u8; 64]),
            owner,
        );

        ledger.append(event).expect("append succeeds");
        assert!(ledger.verify());
    }
}
