#![no_std]

extern crate alloc;

// Make modules public so they can be used by other crates
pub mod capsule;
pub mod event;
pub mod event_payloads;
pub mod ledger;
pub mod primitives;
pub mod starter;
pub mod relationship;
pub mod slot;

// Re-export commonly used types
pub use primitives::{PubKey, Signature, StarterId, StarterKind, Timestamp, Network};
pub use event::{Event, EventKind, PROTOCOL_VERSION};
pub use event_payloads::{
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
pub use starter::Starter;
pub use ledger::Ledger;
