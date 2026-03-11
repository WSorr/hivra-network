use crate::event::EventKind;
use crate::event_payloads::{
    EventPayload, InvitationAcceptedPayload, InvitationExpiredPayload, InvitationRejectedPayload,
    InvitationSentPayload, RejectReason,
};
use crate::ledger::Ledger;
use crate::primitives::SlotIndex;
use crate::slot::SlotLayout;
use crate::{PubKey, StarterId, StarterKind};
use alloc::vec::Vec;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InvitationStatus {
    Pending,
    Accepted {
        created_starter_id: StarterId,
        from_pubkey: PubKey,
    },
    Rejected {
        reason: RejectReason,
    },
    Expired,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InvitationRecord {
    pub invitation_id: [u8; 32],
    pub starter_id: StarterId,
    pub peer_pubkey: PubKey,
    pub status: InvitationStatus,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PlannedStarterCreation {
    pub slot: SlotIndex,
    pub kind: StarterKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AcceptPlan {
    UseExistingStarter {
        relationship_starter_id: StarterId,
        created_starter: Option<PlannedStarterCreation>,
    },
    CreateStarterInEmptySlot {
        slot: SlotIndex,
        kind: StarterKind,
    },
    NoCapacity,
}

pub fn pending_invitations(ledger: &Ledger) -> Vec<InvitationRecord> {
    invitations_with_status(ledger)
        .into_iter()
        .filter(|invitation| invitation.status == InvitationStatus::Pending)
        .collect()
}

pub fn pending_invitation_count(ledger: &Ledger) -> usize {
    pending_invitations(ledger).len()
}

pub fn find_invitation(ledger: &Ledger, invitation_id: [u8; 32]) -> Option<InvitationRecord> {
    invitations_with_status(ledger)
        .into_iter()
        .find(|invitation| invitation.invitation_id == invitation_id)
}

pub fn plan_accept_for_kind(
    ledger: &Ledger,
    slots: &SlotLayout,
    kind: StarterKind,
) -> AcceptPlan {
    let starter_kinds = active_starter_kinds(slots, ledger);
    let matching_starter_id = slots
        .entries_with_kinds(ledger)
        .iter()
        .find_map(|entry| (entry.starter_kind == Some(kind)).then_some(entry.state))
        .and_then(|state| match state {
            crate::slot::SlotState::Occupied(id) | crate::slot::SlotState::Locked(id) => Some(id),
            crate::slot::SlotState::Empty => None,
        });
    let empty_slot = slots.find_first_empty();

    if let Some(relationship_starter_id) = matching_starter_id {
        let created_starter = empty_slot.and_then(|slot| {
            first_missing_kind(&starter_kinds).map(|kind| PlannedStarterCreation { slot, kind })
        });

        return AcceptPlan::UseExistingStarter {
            relationship_starter_id,
            created_starter,
        };
    }

    if let Some(slot) = empty_slot {
        AcceptPlan::CreateStarterInEmptySlot { slot, kind }
    } else {
        AcceptPlan::NoCapacity
    }
}

pub fn invitations_with_status(ledger: &Ledger) -> Vec<InvitationRecord> {
    let mut invitations = Vec::new();

    for event in ledger.events() {
        if event.kind() != EventKind::InvitationSent {
            continue;
        }

        let Ok(payload) = InvitationSentPayload::from_bytes(event.payload()) else {
            continue;
        };

        invitations.push(InvitationRecord {
            invitation_id: payload.invitation_id,
            starter_id: payload.starter_id,
            peer_pubkey: payload.to_pubkey,
            status: invitation_status(ledger, payload.invitation_id),
        });
    }

    invitations
}

pub fn invitation_status(ledger: &Ledger, invitation_id: [u8; 32]) -> InvitationStatus {
    for event in ledger.events() {
        match event.kind() {
            EventKind::InvitationAccepted => {
                let Ok(payload) = InvitationAcceptedPayload::from_bytes(event.payload()) else {
                    continue;
                };
                if payload.invitation_id == invitation_id {
                    return InvitationStatus::Accepted {
                        created_starter_id: payload.created_starter_id,
                        from_pubkey: payload.from_pubkey,
                    };
                }
            }
            EventKind::InvitationRejected => {
                let Ok(payload) = InvitationRejectedPayload::from_bytes(event.payload()) else {
                    continue;
                };
                if payload.invitation_id == invitation_id {
                    return InvitationStatus::Rejected {
                        reason: payload.reason,
                    };
                }
            }
            EventKind::InvitationExpired => {
                let Ok(payload) = InvitationExpiredPayload::from_bytes(event.payload()) else {
                    continue;
                };
                if payload.invitation_id == invitation_id {
                    return InvitationStatus::Expired;
                }
            }
            _ => {}
        }
    }

    InvitationStatus::Pending
}

fn active_starter_kinds(slots: &SlotLayout, ledger: &Ledger) -> [bool; 5] {
    let mut kinds = [false; 5];

    for entry in slots.entries_with_kinds(ledger) {
        if let Some(kind) = entry.starter_kind {
            kinds[kind.to_byte() as usize] = true;
        }
    }

    kinds
}

fn first_missing_kind(active_kinds: &[bool; 5]) -> Option<StarterKind> {
    [
        StarterKind::Juice,
        StarterKind::Spark,
        StarterKind::Seed,
        StarterKind::Pulse,
        StarterKind::Kick,
    ]
    .into_iter()
    .find(|kind| !active_kinds[kind.to_byte() as usize])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::Event;
    use crate::event_payloads::StarterCreatedPayload;
    use crate::slot::SlotLayout;
    use crate::{Network, Signature, Timestamp};

    fn append_event(ledger: &mut Ledger, kind: EventKind, payload: &[u8], timestamp: u64) {
        let owner = *ledger.owner();
        ledger
            .append(Event::new(
                kind,
                payload.to_vec(),
                Timestamp::from(timestamp),
                Signature::from([0u8; 64]),
                owner,
            ))
            .expect("append succeeds");
    }

    fn starter_created(starter_byte: u8, kind: StarterKind) -> Vec<u8> {
        StarterCreatedPayload {
            starter_id: StarterId::from([starter_byte; 32]),
            nonce: [starter_byte; 32],
            kind,
            network: Network::Neste.to_byte(),
        }
        .to_bytes()
    }

    #[test]
    fn invitation_projection_tracks_pending_and_resolution() {
        let owner = PubKey::from([1u8; 32]);
        let peer = PubKey::from([2u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::InvitationSent,
            &InvitationSentPayload {
                invitation_id: [9u8; 32],
                starter_id: StarterId::from([3u8; 32]),
                to_pubkey: peer,
            }
            .to_bytes(),
            1,
        );

        assert_eq!(pending_invitation_count(&ledger), 1);
        assert_eq!(invitation_status(&ledger, [9u8; 32]), InvitationStatus::Pending);

        append_event(
            &mut ledger,
            EventKind::InvitationRejected,
            &InvitationRejectedPayload {
                invitation_id: [9u8; 32],
                reason: RejectReason::Other,
            }
            .to_bytes(),
            2,
        );

        assert_eq!(pending_invitation_count(&ledger), 0);
        assert_eq!(
            invitation_status(&ledger, [9u8; 32]),
            InvitationStatus::Rejected {
                reason: RejectReason::Other,
            }
        );
    }

    #[test]
    fn accept_plan_prefers_existing_matching_starter() {
        let owner = PubKey::from([1u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(4, StarterKind::Seed),
            1,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(5, StarterKind::Juice),
            2,
        );

        let slots = SlotLayout::from_ledger(&ledger);

        assert_eq!(
            plan_accept_for_kind(&ledger, &slots, StarterKind::Seed),
            AcceptPlan::UseExistingStarter {
                relationship_starter_id: StarterId::from([4u8; 32]),
                created_starter: Some(PlannedStarterCreation {
                    slot: SlotIndex::new(2).unwrap(),
                    kind: StarterKind::Spark,
                }),
            }
        );
    }

    #[test]
    fn accept_plan_uses_empty_slot_when_kind_is_missing() {
        let owner = PubKey::from([1u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Juice),
            1,
        );

        let slots = SlotLayout::from_ledger(&ledger);

        assert_eq!(
            plan_accept_for_kind(&ledger, &slots, StarterKind::Kick),
            AcceptPlan::CreateStarterInEmptySlot {
                slot: SlotIndex::new(1).unwrap(),
                kind: StarterKind::Kick,
            }
        );
    }

    #[test]
    fn accept_plan_detects_full_capsule_without_matching_kind() {
        let owner = PubKey::from([1u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Juice),
            1,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(2, StarterKind::Spark),
            2,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(3, StarterKind::Seed),
            3,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(4, StarterKind::Pulse),
            4,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(5, StarterKind::Kick),
            5,
        );

        let slots = SlotLayout::from_ledger(&ledger);

        assert_eq!(
            plan_accept_for_kind(&ledger, &slots, StarterKind::Juice),
            AcceptPlan::UseExistingStarter {
                relationship_starter_id: StarterId::from([1u8; 32]),
                created_starter: None,
            }
        );
        assert_eq!(
            plan_accept_for_kind(&ledger, &slots, StarterKind::Kick),
            AcceptPlan::UseExistingStarter {
                relationship_starter_id: StarterId::from([5u8; 32]),
                created_starter: None,
            }
        );
    }
}
