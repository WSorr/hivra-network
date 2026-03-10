use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct PubKey(#[serde(with = "serde_bytes")] [u8; 32]);

impl PubKey {
    pub const fn from(bytes: [u8; 32]) -> Self { Self(bytes) }
    pub const fn as_bytes(&self) -> &[u8; 32] { &self.0 }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Signature(#[serde(with = "serde_bytes")] [u8; 64]);

impl Signature {
    pub const fn from(bytes: [u8; 64]) -> Self { Self(bytes) }
    pub const fn as_bytes(&self) -> &[u8; 64] { &self.0 }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct StarterId(#[serde(with = "serde_bytes")] [u8; 32]);

impl StarterId {
    pub const fn from(bytes: [u8; 32]) -> Self { Self(bytes) }
    pub const fn new(bytes: [u8; 32]) -> Self { Self::from(bytes) }
    pub const fn as_bytes(&self) -> &[u8; 32] { &self.0 }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub struct Timestamp(u64);

impl Timestamp {
    pub const fn from(value: u64) -> Self { Self(value) }
    pub const fn as_u64(&self) -> u64 { self.0 }
}

impl From<u64> for Timestamp {
    fn from(value: u64) -> Self { Self(value) }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum StarterKind {
    Juice = 0,
    Spark = 1,
    Seed = 2,
    Pulse = 3,
    Kick = 4,
}

impl StarterKind {
    pub fn to_byte(&self) -> u8 {
        *self as u8
    }

    pub fn from_u8(value: u8) -> Option<Self> {
        match value {
            0 => Some(StarterKind::Juice),
            1 => Some(StarterKind::Spark),
            2 => Some(StarterKind::Seed),
            3 => Some(StarterKind::Pulse),
            4 => Some(StarterKind::Kick),
            _ => None,
        }
    }
}

/// Network type (Hood = test, Neste = main)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum Network {
    Hood = 0,
    Neste = 1,
}

impl Network {
    pub fn to_byte(&self) -> u8 {
        *self as u8
    }

    pub fn from_u8(value: u8) -> Option<Self> {
        match value {
            0 => Some(Network::Hood),
            1 => Some(Network::Neste),
            _ => None,
        }
    }
}

/// Slot index (0-4)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct SlotIndex(u8);

impl SlotIndex {
    pub fn new(value: u8) -> Option<Self> {
        if value < 5 {
            Some(Self(value))
        } else {
            None
        }
    }

    pub fn as_u8(&self) -> u8 {
        self.0
    }
}
