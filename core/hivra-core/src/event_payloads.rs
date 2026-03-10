//! Binary payload schemas for Hivra Core domain events.

use crate::{EventKind, PubKey, StarterId, StarterKind};
use alloc::vec;
use alloc::vec::Vec;

pub trait EventPayload {
    fn kind() -> EventKind;
    fn to_bytes(&self) -> Vec<u8>;
    fn from_bytes(bytes: &[u8]) -> Result<Self, &'static str>
    where
        Self: Sized;
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RejectReason {
    EmptySlot = 0,
    Other = 1,
}

impl RejectReason {
    pub fn from_u8(value: u8) -> Result<Self, &'static str> {
        match value {
            0 => Ok(Self::EmptySlot),
            1 => Ok(Self::Other),
            _ => Err("invalid reject reason"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapsuleCreatedPayload {
    pub network: u8,
    pub capsule_type: u8,
}

impl CapsuleCreatedPayload {
    pub fn new(network: u8, capsule_type: u8, _reserved: [u8; 32]) -> Self {
        Self {
            network,
            capsule_type,
        }
    }
}

impl EventPayload for CapsuleCreatedPayload {
    fn kind() -> EventKind {
        EventKind::CapsuleCreated
    }

    fn to_bytes(&self) -> Vec<u8> {
        vec![self.network, self.capsule_type]
    }

    fn from_bytes(bytes: &[u8]) -> Result<Self, &'static str> {
        if bytes.len() != 2 {
            return Err("invalid capsule_created payload length");
        }
        Ok(Self {
            network: bytes[0],
            capsule_type: bytes[1],
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InvitationSentPayload {
    pub invitation_id: [u8; 32],
    pub starter_id: StarterId,
    pub to_pubkey: PubKey,
}

impl EventPayload for InvitationSentPayload {
    fn kind() -> EventKind {
        EventKind::InvitationSent
    }

    fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(96);
        out.extend_from_slice(&self.invitation_id);
        out.extend_from_slice(self.starter_id.as_bytes());
        out.extend_from_slice(self.to_pubkey.as_bytes());
        out
    }

    fn from_bytes(bytes: &[u8]) -> Result<Self, &'static str> {
        if bytes.len() != 96 {
            return Err("invalid invitation_sent payload length");
        }
        Ok(Self {
            invitation_id: read_fixed_32(bytes, 0),
            starter_id: StarterId::from(read_fixed_32(bytes, 32)),
            to_pubkey: PubKey::from(read_fixed_32(bytes, 64)),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InvitationAcceptedPayload {
    pub invitation_id: [u8; 32],
    pub from_pubkey: PubKey,
    pub created_starter_id: StarterId,
}

impl EventPayload for InvitationAcceptedPayload {
    fn kind() -> EventKind {
        EventKind::InvitationAccepted
    }

    fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(96);
        out.extend_from_slice(&self.invitation_id);
        out.extend_from_slice(self.from_pubkey.as_bytes());
        out.extend_from_slice(self.created_starter_id.as_bytes());
        out
    }

    fn from_bytes(bytes: &[u8]) -> Result<Self, &'static str> {
        if bytes.len() != 96 {
            return Err("invalid invitation_accepted payload length");
        }
        Ok(Self {
            invitation_id: read_fixed_32(bytes, 0),
            from_pubkey: PubKey::from(read_fixed_32(bytes, 32)),
            created_starter_id: StarterId::from(read_fixed_32(bytes, 64)),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InvitationRejectedPayload {
    pub invitation_id: [u8; 32],
    pub reason: RejectReason,
}

impl EventPayload for InvitationRejectedPayload {
    fn kind() -> EventKind {
        EventKind::InvitationRejected
    }

    fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(33);
        out.extend_from_slice(&self.invitation_id);
        out.push(self.reason as u8);
        out
    }

    fn from_bytes(bytes: &[u8]) -> Result<Self, &'static str> {
        if bytes.len() != 33 {
            return Err("invalid invitation_rejected payload length");
        }
        Ok(Self {
            invitation_id: read_fixed_32(bytes, 0),
            reason: RejectReason::from_u8(bytes[32])?,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InvitationExpiredPayload {
    pub invitation_id: [u8; 32],
}

impl EventPayload for InvitationExpiredPayload {
    fn kind() -> EventKind {
        EventKind::InvitationExpired
    }

    fn to_bytes(&self) -> Vec<u8> {
        self.invitation_id.to_vec()
    }

    fn from_bytes(bytes: &[u8]) -> Result<Self, &'static str> {
        if bytes.len() != 32 {
            return Err("invalid invitation_expired payload length");
        }
        Ok(Self {
            invitation_id: read_fixed_32(bytes, 0),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StarterCreatedPayload {
    pub starter_id: StarterId,
    pub nonce: [u8; 32],
    pub kind: StarterKind,
    pub network: u8,
}

impl EventPayload for StarterCreatedPayload {
    fn kind() -> EventKind {
        EventKind::StarterCreated
    }

    fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(66);
        out.extend_from_slice(self.starter_id.as_bytes());
        out.extend_from_slice(&self.nonce);
        out.push(self.kind as u8);
        out.push(self.network);
        out
    }

    fn from_bytes(bytes: &[u8]) -> Result<Self, &'static str> {
        if bytes.len() != 66 {
            return Err("invalid starter_created payload length");
        }
        let kind = StarterKind::from_u8(bytes[64]).ok_or("invalid starter kind")?;
        Ok(Self {
            starter_id: StarterId::from(read_fixed_32(bytes, 0)),
            nonce: read_fixed_32(bytes, 32),
            kind,
            network: bytes[65],
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StarterBurnedPayload {
    pub starter_id: StarterId,
    pub reason: u8,
}

impl EventPayload for StarterBurnedPayload {
    fn kind() -> EventKind {
        EventKind::StarterBurned
    }

    fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(33);
        out.extend_from_slice(self.starter_id.as_bytes());
        out.push(self.reason);
        out
    }

    fn from_bytes(bytes: &[u8]) -> Result<Self, &'static str> {
        if bytes.len() != 33 {
            return Err("invalid starter_burned payload length");
        }
        Ok(Self {
            starter_id: StarterId::from(read_fixed_32(bytes, 0)),
            reason: bytes[32],
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RelationshipEstablishedPayload {
    pub peer_pubkey: PubKey,
    pub own_starter_id: StarterId,
    pub peer_starter_id: StarterId,
    pub kind: StarterKind,
}

impl EventPayload for RelationshipEstablishedPayload {
    fn kind() -> EventKind {
        EventKind::RelationshipEstablished
    }

    fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(97);
        out.extend_from_slice(self.peer_pubkey.as_bytes());
        out.extend_from_slice(self.own_starter_id.as_bytes());
        out.extend_from_slice(self.peer_starter_id.as_bytes());
        out.push(self.kind as u8);
        out
    }

    fn from_bytes(bytes: &[u8]) -> Result<Self, &'static str> {
        if bytes.len() != 97 {
            return Err("invalid relationship_established payload length");
        }
        let kind = StarterKind::from_u8(bytes[96]).ok_or("invalid starter kind")?;
        Ok(Self {
            peer_pubkey: PubKey::from(read_fixed_32(bytes, 0)),
            own_starter_id: StarterId::from(read_fixed_32(bytes, 32)),
            peer_starter_id: StarterId::from(read_fixed_32(bytes, 64)),
            kind,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RelationshipBrokenPayload {
    pub peer_pubkey: PubKey,
    pub own_starter_id: StarterId,
}

impl EventPayload for RelationshipBrokenPayload {
    fn kind() -> EventKind {
        EventKind::RelationshipBroken
    }

    fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(64);
        out.extend_from_slice(self.peer_pubkey.as_bytes());
        out.extend_from_slice(self.own_starter_id.as_bytes());
        out
    }

    fn from_bytes(bytes: &[u8]) -> Result<Self, &'static str> {
        if bytes.len() != 64 {
            return Err("invalid relationship_broken payload length");
        }
        Ok(Self {
            peer_pubkey: PubKey::from(read_fixed_32(bytes, 0)),
            own_starter_id: StarterId::from(read_fixed_32(bytes, 32)),
        })
    }
}

fn read_fixed_32(bytes: &[u8], start: usize) -> [u8; 32] {
    let mut out = [0u8; 32];
    out.copy_from_slice(&bytes[start..start + 32]);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_invitation_rejected_roundtrip() {
        let payload = InvitationRejectedPayload {
            invitation_id: [9u8; 32],
            reason: RejectReason::EmptySlot,
        };

        let bytes = payload.to_bytes();
        let parsed = InvitationRejectedPayload::from_bytes(&bytes).unwrap();
        assert_eq!(parsed, payload);
    }

    #[test]
    fn test_relationship_established_roundtrip() {
        let payload = RelationshipEstablishedPayload {
            peer_pubkey: PubKey::from([1u8; 32]),
            own_starter_id: StarterId::from([2u8; 32]),
            peer_starter_id: StarterId::from([3u8; 32]),
            kind: StarterKind::Seed,
        };

        let bytes = payload.to_bytes();
        let parsed = RelationshipEstablishedPayload::from_bytes(&bytes).unwrap();
        assert_eq!(parsed, payload);
    }
}
