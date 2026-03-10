//! Starter entity - unique non-transferable identifier

use crate::primitives::{PubKey, StarterId, StarterKind, Timestamp, Network};
use sha2::{Sha256, Digest};

/// Starter states
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StarterState {
    Active,
    Burned,
}

/// Starter entity
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Starter {
    id: StarterId,
    owner: PubKey,
    kind: StarterKind,
    network: Network,
    origin_invitation: Option<[u8; 32]>,
    created_at: Timestamp,
    state: StarterState,
}

impl Starter {
    /// Create a new starter
    pub fn new(
        id: StarterId,
        owner: PubKey,
        kind: StarterKind,
        network: Network,
        origin_invitation: Option<[u8; 32]>,
        created_at: Timestamp,
    ) -> Self {
        Self {
            id,
            owner,
            kind,
            network,
            origin_invitation,
            created_at,
            state: StarterState::Active,
        }
    }

    /// Derive starter ID deterministically from protocol fields.
    ///
    /// v3.2 formula:
    /// SHA256(owner_pubkey || network || kind || creation_nonce)
    pub fn derive_id(
        owner_pubkey: &PubKey,
        kind: StarterKind,
        network: Network,
        creation_nonce: &[u8; 32],
    ) -> StarterId {
        let mut hasher = Sha256::new();
        hasher.update(owner_pubkey.as_bytes());
        hasher.update(&[network as u8]);
        hasher.update(&[kind as u8]);
        hasher.update(creation_nonce);

        let hash = hasher.finalize();
        let mut id = [0u8; 32];
        id.copy_from_slice(&hash);
        StarterId::new(id)
    }

    /// Get starter ID
    pub fn id(&self) -> StarterId {
        self.id
    }

    /// Get starter kind
    pub fn kind(&self) -> StarterKind {
        self.kind
    }

    /// Get owner
    pub fn owner(&self) -> PubKey {
        self.owner
    }

    /// Get network
    pub fn network(&self) -> Network {
        self.network
    }

    /// Get state
    pub fn state(&self) -> StarterState {
        self.state
    }

    /// Check if starter is active
    pub fn is_active(&self) -> bool {
        self.state == StarterState::Active
    }

    /// Burn the starter
    pub fn burn(&mut self) {
        self.state = StarterState::Burned;
    }

    /// Get origin invitation
    pub fn origin_invitation(&self) -> Option<[u8; 32]> {
        self.origin_invitation
    }

    /// Get creation time
    pub fn created_at(&self) -> Timestamp {
        self.created_at
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::primitives::{PubKey, Timestamp};

    #[test]
    fn test_starter_creation() {
        let id = StarterId::new([0u8; 32]);
        let owner = PubKey::from([1u8; 32]);
        let kind = StarterKind::Juice;
        let network = Network::Neste;
        let time = Timestamp::from(1000);

        let starter = Starter::new(id, owner, kind, network, None, time);
        
        assert_eq!(starter.id(), id);
        assert_eq!(starter.kind(), kind);
        assert_eq!(starter.owner(), owner);
        assert_eq!(starter.network(), network);
        assert!(starter.is_active());
        assert_eq!(starter.created_at(), time);
    }

    #[test]
    fn test_starter_burn() {
        let id = StarterId::new([0u8; 32]);
        let owner = PubKey::from([1u8; 32]);
        let kind = StarterKind::Juice;
        let network = Network::Neste;
        let time = Timestamp::from(1000);

        let mut starter = Starter::new(id, owner, kind, network, None, time);
        assert!(starter.is_active());
        
        starter.burn();
        assert!(!starter.is_active());
        assert_eq!(starter.state(), StarterState::Burned);
    }

    #[test]
    fn test_derive_id_deterministic() {
        let owner = PubKey::from([0x42u8; 32]);
        let kind = StarterKind::Spark;
        let network = Network::Neste;
        let nonce = [7u8; 32];

        let id1 = Starter::derive_id(&owner, kind, network, &nonce);
        let id2 = Starter::derive_id(&owner, kind, network, &nonce);

        // Same inputs should produce same ID
        assert_eq!(id1, id2);

        // Different nonce should produce different ID
        let id3 = Starter::derive_id(&owner, kind, network, &[8u8; 32]);
        assert_ne!(id1, id3);

        // Different kind should produce different ID
        let id4 = Starter::derive_id(&owner, StarterKind::Pulse, network, &nonce);
        assert_ne!(id1, id4);

        // Different network should produce different ID
        let id5 = Starter::derive_id(&owner, kind, Network::Hood, &nonce);
        assert_ne!(id1, id5);

        // Different owner should produce different ID
        let id6 = Starter::derive_id(&PubKey::from([0x43u8; 32]), kind, network, &nonce);
        assert_ne!(id1, id6);
    }

    #[test]
    fn test_derive_id_protocol_field_order_stable() {
        let owner = PubKey::from([1u8; 32]);
        let kind = StarterKind::Juice;
        let network = Network::Hood;
        let nonce = [2u8; 32];

        let protocol_id = Starter::derive_id(&owner, kind, network, &nonce);
        let mut hasher = Sha256::new();
        hasher.update(owner.as_bytes());
        hasher.update(&[network as u8]);
        hasher.update(&[kind as u8]);
        hasher.update(&nonce);
        let expected = hasher.finalize();
        let mut expected_bytes = [0u8; 32];
        expected_bytes.copy_from_slice(&expected);

        assert_eq!(protocol_id, StarterId::new(expected_bytes));
    }
}
