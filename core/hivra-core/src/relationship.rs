//! Relationship entity.
//!
//! A Relationship is a fact of mutual recognition between two Capsules.
//! One starter can participate in multiple relationships.

use crate::{PubKey, StarterId, StarterKind, Timestamp};
use alloc::vec::Vec;

/// A relationship between two capsules.
///
/// Each relationship is based on a specific starter kind.
/// One starter can have multiple relationships with different peers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Relationship {
    /// Peer's public key
    peer: PubKey,

    /// Own starter ID used in this relationship
    own_starter_id: StarterId,

    /// Peer's starter ID (if known)
    peer_starter_id: StarterId,

    /// Kind of starter (Juice, Spark, Seed, Pulse, Kick)
    kind: StarterKind,

    /// When the relationship was established
    established_at: Timestamp,
}

impl Relationship {
    /// Creates a new relationship.
    pub fn new(
        peer: PubKey,
        own_starter_id: StarterId,
        peer_starter_id: StarterId,
        kind: StarterKind,
        established_at: Timestamp,
    ) -> Self {
        Self {
            peer,
            own_starter_id,
            peer_starter_id,
            kind,
            established_at,
        }
    }

    /// Returns the peer's public key.
    pub const fn peer(&self) -> &PubKey {
        &self.peer
    }

    /// Returns the own starter ID used in this relationship.
    pub const fn own_starter_id(&self) -> &StarterId {
        &self.own_starter_id
    }

    /// Returns the peer's starter ID.
    pub const fn peer_starter_id(&self) -> &StarterId {
        &self.peer_starter_id
    }

    /// Returns the kind of starter this relationship is based on.
    pub const fn kind(&self) -> StarterKind {
        self.kind
    }

    /// Returns when the relationship was established.
    pub const fn established_at(&self) -> Timestamp {
        self.established_at
    }

    /// Checks if this relationship involves a specific starter.
    pub fn involves_starter(&self, starter_id: &StarterId) -> bool {
        &self.own_starter_id == starter_id || &self.peer_starter_id == starter_id
    }

    /// Checks if this relationship is with a specific peer.
    pub fn is_with_peer(&self, peer: &PubKey) -> bool {
        &self.peer == peer
    }
}

/// Collection of relationships.
///
/// Provides methods to query and manage relationships.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Relationships {
    /// List of active relationships
    active: Vec<Relationship>,
}

impl Relationships {
    /// Creates a new empty relationships collection.
    pub fn new() -> Self {
        Self {
            active: Vec::new(),
        }
    }

    /// Returns all active relationships.
    pub fn all(&self) -> &[Relationship] {
        &self.active
    }

    /// Returns relationships with a specific peer.
    pub fn with_peer(&self, peer: &PubKey) -> Vec<&Relationship> {
        self.active
            .iter()
            .filter(|r: &&Relationship| r.is_with_peer(peer))
            .collect()
    }

    /// Returns relationships where the given starter is the local (own) starter.
    pub fn for_starter(&self, starter_id: &StarterId) -> Vec<&Relationship> {
        self.active
            .iter()
            .filter(|r: &&Relationship| r.own_starter_id() == starter_id)
            .collect()
    }

    /// Returns relationships of a specific kind.
    pub fn of_kind(&self, kind: StarterKind) -> Vec<&Relationship> {
        self.active
            .iter()
            .filter(|r: &&Relationship| r.kind() == kind)
            .collect()
    }

    /// Adds a new relationship.
    ///
    /// Returns `false` if relationship already exists.
    pub fn add(&mut self, relationship: Relationship) -> bool {
        // Check for duplicate (same peer and same own starter)
        let exists = self.active.iter().any(|r: &Relationship| {
            r.peer() == relationship.peer() && 
            r.own_starter_id() == relationship.own_starter_id()
        });

        if exists {
            false
        } else {
            self.active.push(relationship);
            true
        }
    }

    /// Removes a relationship with a specific peer and starter.
    ///
    /// Returns the removed relationship if found.
    pub fn remove(&mut self, peer: &PubKey, own_starter_id: &StarterId) -> Option<Relationship> {
        let pos = self.active.iter().position(|r: &Relationship| {
            r.is_with_peer(peer) && r.own_starter_id() == own_starter_id
        });

        pos.map(|idx| self.active.remove(idx))
    }

    /// Removes all relationships for a specific starter (when starter is burned).
    pub fn remove_all_for_starter(&mut self, starter_id: &StarterId) -> Vec<Relationship> {
        let mut removed = Vec::new();
        self.active.retain(|r: &Relationship| {
            if r.involves_starter(starter_id) {
                removed.push(r.clone());
                false
            } else {
                true
            }
        });
        removed
    }

    /// Removes all relationships with a specific peer.
    pub fn remove_all_with_peer(&mut self, peer: &PubKey) -> Vec<Relationship> {
        let mut removed = Vec::new();
        self.active.retain(|r: &Relationship| {
            if r.is_with_peer(peer) {
                removed.push(r.clone());
                false
            } else {
                true
            }
        });
        removed
    }

    /// Checks if a relationship exists with a specific peer and starter.
    pub fn exists(&self, peer: &PubKey, own_starter_id: &StarterId) -> bool {
        self.active.iter().any(|r: &Relationship| {
            r.is_with_peer(peer) && r.own_starter_id() == own_starter_id
        })
    }

    /// Returns the number of active relationships.
    pub fn len(&self) -> usize {
        self.active.len()
    }

    /// Returns true if there are no relationships.
    pub fn is_empty(&self) -> bool {
        self.active.is_empty()
    }
}

impl Default for Relationships {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_pubkey(id: u8) -> PubKey {
        PubKey::from([id; 32])
    }

    fn test_starter_id(id: u8) -> StarterId {
        StarterId::new([id; 32])
    }

    fn create_test_relationship(
        peer_id: u8,
        own_id: u8,
        peer_starter_id: u8,
        kind: StarterKind,
        time: u64,
    ) -> Relationship {
        Relationship::new(
            test_pubkey(peer_id),
            test_starter_id(own_id),
            test_starter_id(peer_starter_id),
            kind,
            Timestamp::from(time),
        )
    }

    #[test]
    fn test_relationship_creation() {
        let rel = create_test_relationship(
            1, 2, 3, 
            StarterKind::Juice, 
            1234567890
        );

        assert_eq!(rel.peer(), &test_pubkey(1));
        assert_eq!(rel.own_starter_id(), &test_starter_id(2));
        assert_eq!(rel.peer_starter_id(), &test_starter_id(3));
        assert_eq!(rel.kind(), StarterKind::Juice);
        assert_eq!(rel.established_at(), Timestamp::from(1234567890));
    }

    #[test]
    fn test_relationships_collection() {
        let mut rels = Relationships::new();
        assert!(rels.is_empty());

        let rel1 = create_test_relationship(1, 1, 1, StarterKind::Juice, 1000);
        let rel2 = create_test_relationship(2, 1, 2, StarterKind::Juice, 1001);
        let rel3 = create_test_relationship(3, 2, 3, StarterKind::Spark, 1002);

        // Add relationships
        assert!(rels.add(rel1));
        assert!(rels.add(rel2));
        assert!(rels.add(rel3));

        assert_eq!(rels.len(), 3);
        assert!(!rels.is_empty());

        // Check duplicates
        let duplicate = create_test_relationship(1, 1, 4, StarterKind::Juice, 1003);
        assert!(!rels.add(duplicate)); // Should fail

        // Query by peer
        let with_peer1 = rels.with_peer(&test_pubkey(1));
        assert_eq!(with_peer1.len(), 1);
        assert_eq!(with_peer1[0].peer(), &test_pubkey(1));

        // Query by starter
        let for_starter1 = rels.for_starter(&test_starter_id(1));
        assert_eq!(for_starter1.len(), 2); // rel1 and rel2

        let for_starter2 = rels.for_starter(&test_starter_id(2));
        assert_eq!(for_starter2.len(), 1); // rel3

        // Query by kind
        let juice_rels = rels.of_kind(StarterKind::Juice);
        assert_eq!(juice_rels.len(), 2);
        let spark_rels = rels.of_kind(StarterKind::Spark);
        assert_eq!(spark_rels.len(), 1);
    }

    #[test]
    fn test_remove_relationship() {
        let mut rels = Relationships::new();

        let rel1 = create_test_relationship(1, 1, 1, StarterKind::Juice, 1000);
        let rel2 = create_test_relationship(2, 1, 2, StarterKind::Juice, 1001);

        rels.add(rel1);
        rels.add(rel2);
        assert_eq!(rels.len(), 2);

        // Remove specific relationship
        let removed = rels.remove(&test_pubkey(1), &test_starter_id(1));
        assert!(removed.is_some());
        assert_eq!(rels.len(), 1);
        assert!(!rels.exists(&test_pubkey(1), &test_starter_id(1)));
        assert!(rels.exists(&test_pubkey(2), &test_starter_id(1)));

        // Remove non-existent
        let removed = rels.remove(&test_pubkey(3), &test_starter_id(3));
        assert!(removed.is_none());
    }

    #[test]
    fn test_remove_all_for_starter() {
        let mut rels = Relationships::new();

        // Starter 1 has relationships with peers 1 and 2
        rels.add(create_test_relationship(1, 1, 1, StarterKind::Juice, 1000));
        rels.add(create_test_relationship(2, 1, 2, StarterKind::Juice, 1001));
        // Starter 2 has relationship with peer 3
        rels.add(create_test_relationship(3, 2, 3, StarterKind::Spark, 1002));

        assert_eq!(rels.len(), 3);

        // Remove all for starter 1
        let removed = rels.remove_all_for_starter(&test_starter_id(1));
        assert_eq!(removed.len(), 2);
        assert_eq!(rels.len(), 1);

        // Only starter 2's relationship remains
        let remaining = rels.all();
        assert_eq!(remaining[0].own_starter_id(), &test_starter_id(2));
    }

    #[test]
    fn test_remove_all_with_peer() {
        let mut rels = Relationships::new();

        // Peer 1 has relationships with starter 1 and starter 2
        rels.add(create_test_relationship(1, 1, 1, StarterKind::Juice, 1000));
        rels.add(create_test_relationship(1, 2, 2, StarterKind::Spark, 1001));
        // Peer 2 has relationship with starter 1
        rels.add(create_test_relationship(2, 1, 3, StarterKind::Juice, 1002));

        assert_eq!(rels.len(), 3);

        // Remove all with peer 1
        let removed = rels.remove_all_with_peer(&test_pubkey(1));
        assert_eq!(removed.len(), 2);
        assert_eq!(rels.len(), 1);

        // Only peer 2's relationship remains
        let remaining = rels.all();
        assert_eq!(remaining[0].peer(), &test_pubkey(2));
    }

    #[test]
    fn test_relationship_invariants() {
        let rel = create_test_relationship(1, 1, 1, StarterKind::Juice, 1000);

        // Test involves_starter
        assert!(rel.involves_starter(&test_starter_id(1)));
        assert!(!rel.involves_starter(&test_starter_id(2)));

        // Test is_with_peer
        assert!(rel.is_with_peer(&test_pubkey(1)));
        assert!(!rel.is_with_peer(&test_pubkey(2)));
    }
}
