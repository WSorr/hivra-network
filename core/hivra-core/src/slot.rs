use crate::event::EventKind;
use crate::event_payloads::{
    EventPayload, InvitationAcceptedPayload, InvitationExpiredPayload, InvitationRejectedPayload,
    InvitationSentPayload, StarterBurnedPayload, StarterCreatedPayload,
};
use crate::ledger::Ledger;
use crate::primitives::{SlotIndex, StarterId, StarterKind};

/// Projected slot state derived from the ledger.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SlotState {
    Empty,
    Occupied(StarterId),
    Locked(StarterId),
}

/// Deterministic slot projection.
///
/// Slots are positions with capacity 5. Starter kind is not tied to a slot index.
/// Projection rules:
/// - `StarterCreated` occupies the first free slot.
/// - `StarterBurned` frees the matching slot.
/// - Pending outgoing invitations lock the corresponding starter.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SlotLayout {
    slots: [SlotState; 5],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SlotEntry {
    pub index: SlotIndex,
    pub state: SlotState,
    pub starter_kind: Option<StarterKind>,
}

impl SlotLayout {
    pub fn empty() -> Self {
        Self {
            slots: [
                SlotState::Empty,
                SlotState::Empty,
                SlotState::Empty,
                SlotState::Empty,
                SlotState::Empty,
            ],
        }
    }

    pub fn from_ledger(ledger: &Ledger) -> Self {
        let mut layout = Self::empty();
        let owner = ledger.owner();

        for event in ledger.events() {
            if event.signer() != owner {
                continue;
            }

            match event.kind() {
                EventKind::StarterCreated => {
                    if let Ok(payload) = StarterCreatedPayload::from_bytes(event.payload()) {
                        layout.occupy_first_free(payload.starter_id);
                    }
                }
                EventKind::StarterBurned => {
                    if let Ok(payload) = StarterBurnedPayload::from_bytes(event.payload()) {
                        layout.free_starter(payload.starter_id);
                    }
                }
                _ => {}
            }
        }

        for starter_id in locked_starter_ids(ledger).into_iter().flatten() {
            layout.lock_starter(starter_id);
        }

        layout
    }

    pub fn states(&self) -> &[SlotState; 5] {
        &self.slots
    }

    pub fn state_at(&self, index: SlotIndex) -> SlotState {
        self.slots[index.as_u8() as usize]
    }

    pub fn starter_id_at(&self, index: SlotIndex) -> Option<StarterId> {
        match self.state_at(index) {
            SlotState::Empty => None,
            SlotState::Occupied(id) | SlotState::Locked(id) => Some(id),
        }
    }

    pub fn starter_ids(&self) -> [Option<StarterId>; 5] {
        let mut result = [None, None, None, None, None];
        for idx in 0..5 {
            result[idx] = match self.slots[idx] {
                SlotState::Empty => None,
                SlotState::Occupied(id) | SlotState::Locked(id) => Some(id),
            };
        }
        result
    }

    pub fn entries_with_kinds(&self, ledger: &Ledger) -> [SlotEntry; 5] {
        let starter_kinds = starter_kinds_by_id(ledger);
        core::array::from_fn(|idx| {
            let state = self.slots[idx];
            let starter_kind = match state {
                SlotState::Empty => None,
                SlotState::Occupied(id) | SlotState::Locked(id) => starter_kinds
                    .iter()
                    .find_map(|(starter_id, kind)| (*starter_id == id).then_some(*kind)),
            };

            SlotEntry {
                index: SlotIndex::new(idx as u8).expect("slot index is in range"),
                state,
                starter_kind,
            }
        })
    }

    pub fn find_first_empty(&self) -> Option<SlotIndex> {
        self.slots
            .iter()
            .position(|state| matches!(state, SlotState::Empty))
            .and_then(|idx| SlotIndex::new(idx as u8))
    }

    pub fn find_by_starter(&self, starter_id: StarterId) -> Option<SlotIndex> {
        self.slots
            .iter()
            .position(|state| match state {
                SlotState::Occupied(id) | SlotState::Locked(id) => *id == starter_id,
                SlotState::Empty => false,
            })
            .and_then(|idx| SlotIndex::new(idx as u8))
    }

    pub fn has_matching_starter(&self, ledger: &Ledger, kind: StarterKind) -> bool {
        self.entries_with_kinds(ledger)
            .iter()
            .any(|entry| entry.starter_kind == Some(kind))
    }

    fn occupy_first_free(&mut self, starter_id: StarterId) {
        if let Some(idx) = self
            .slots
            .iter()
            .position(|state| matches!(state, SlotState::Empty))
        {
            self.slots[idx] = SlotState::Occupied(starter_id);
        }
    }

    fn free_starter(&mut self, starter_id: StarterId) {
        if let Some(idx) = self
            .slots
            .iter()
            .position(|state| matches!(state, SlotState::Occupied(id) | SlotState::Locked(id) if *id == starter_id))
        {
            self.slots[idx] = SlotState::Empty;
        }
    }

    fn lock_starter(&mut self, starter_id: StarterId) {
        if let Some(idx) = self
            .slots
            .iter()
            .position(|state| matches!(state, SlotState::Occupied(id) if *id == starter_id))
        {
            self.slots[idx] = SlotState::Locked(starter_id);
        }
    }
}

fn starter_kinds_by_id(ledger: &Ledger) -> [(StarterId, StarterKind); 5] {
    let mut items = [(StarterId::from([0u8; 32]), StarterKind::Juice); 5];
    let mut count = 0usize;
    let owner = ledger.owner();

    for event in ledger.events() {
        if event.signer() != owner {
            continue;
        }

        if event.kind() != EventKind::StarterCreated {
            continue;
        }

        let Ok(payload) = StarterCreatedPayload::from_bytes(event.payload()) else {
            continue;
        };

        if count < items.len() {
            items[count] = (payload.starter_id, payload.kind);
            count += 1;
        }
    }

    items
}

fn locked_starter_ids(ledger: &Ledger) -> [Option<StarterId>; 5] {
    let mut pending: [(Option<[u8; 32]>, Option<StarterId>); 5] =
        [(None, None), (None, None), (None, None), (None, None), (None, None)];
    let owner = ledger.owner();

    for event in ledger.events() {
        match event.kind() {
            EventKind::InvitationSent => {
                if event.signer() != owner {
                    continue;
                }

                let Ok(payload) = InvitationSentPayload::from_bytes(event.payload()) else {
                    continue;
                };

                if let Some(idx) = pending.iter().position(|(invitation, _)| invitation.is_none()) {
                    pending[idx] = (Some(payload.invitation_id), Some(payload.starter_id));
                }
            }
            EventKind::InvitationAccepted => {
                let Ok(payload) = InvitationAcceptedPayload::from_bytes(event.payload()) else {
                    continue;
                };
                clear_pending(&mut pending, payload.invitation_id);
            }
            EventKind::InvitationRejected => {
                let Ok(payload) = InvitationRejectedPayload::from_bytes(event.payload()) else {
                    continue;
                };
                clear_pending(&mut pending, payload.invitation_id);
            }
            EventKind::InvitationExpired => {
                let Ok(payload) = InvitationExpiredPayload::from_bytes(event.payload()) else {
                    continue;
                };
                clear_pending(&mut pending, payload.invitation_id);
            }
            _ => {}
        }
    }

    core::array::from_fn(|idx| pending[idx].1)
}

fn clear_pending(pending: &mut [(Option<[u8; 32]>, Option<StarterId>); 5], invitation_id: [u8; 32]) {
    if let Some(idx) = pending
        .iter()
        .position(|(current_invitation_id, _)| current_invitation_id.is_some_and(|current| current == invitation_id))
    {
        pending[idx] = (None, None);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec::Vec;
    use crate::event::Event;
    use crate::event_payloads::{RejectReason, StarterCreatedPayload};
    use crate::primitives::{Network, PubKey, Signature, Timestamp};

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

    fn append_event_with_signer(
        ledger: &mut Ledger,
        kind: EventKind,
        payload: &[u8],
        timestamp: u64,
        signer: PubKey,
    ) {
        ledger
            .append(Event::new(
                kind,
                payload.to_vec(),
                Timestamp::from(timestamp),
                Signature::from([0u8; 64]),
                signer,
            ))
            .expect("append succeeds");
    }

    #[test]
    fn projects_slots_by_creation_order_not_kind() {
        let owner = PubKey::from([7u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Kick),
            1,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(2, StarterKind::Juice),
            2,
        );

        let layout = SlotLayout::from_ledger(&ledger);

        assert_eq!(
            layout.starter_ids(),
            [
                Some(StarterId::from([1u8; 32])),
                Some(StarterId::from([2u8; 32])),
                None,
                None,
                None,
            ]
        );
        assert!(layout.has_matching_starter(&ledger, StarterKind::Kick));
        assert!(layout.has_matching_starter(&ledger, StarterKind::Juice));
    }

    #[test]
    fn burns_free_slot_and_reuses_first_empty_position() {
        let owner = PubKey::from([7u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Spark),
            1,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(2, StarterKind::Pulse),
            2,
        );
        append_event(
            &mut ledger,
            EventKind::StarterBurned,
            &StarterBurnedPayload {
                starter_id: StarterId::from([1u8; 32]),
                reason: 0,
            }
            .to_bytes(),
            3,
        );
        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(3, StarterKind::Seed),
            4,
        );

        let layout = SlotLayout::from_ledger(&ledger);

        assert_eq!(
            layout.starter_ids(),
            [
                Some(StarterId::from([3u8; 32])),
                Some(StarterId::from([2u8; 32])),
                None,
                None,
                None,
            ]
        );
    }

    #[test]
    fn marks_pending_outgoing_invitation_as_locked_until_finalized() {
        let owner = PubKey::from([7u8; 32]);
        let peer = PubKey::from([8u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Juice),
            1,
        );
        append_event(
            &mut ledger,
            EventKind::InvitationSent,
            &InvitationSentPayload {
                invitation_id: [9u8; 32],
                starter_id: StarterId::from([1u8; 32]),
                to_pubkey: peer,
            }
            .to_bytes(),
            2,
        );

        let locked_layout = SlotLayout::from_ledger(&ledger);
        assert_eq!(
            locked_layout.state_at(SlotIndex::new(0).unwrap()),
            SlotState::Locked(StarterId::from([1u8; 32]))
        );

        append_event(
            &mut ledger,
            EventKind::InvitationRejected,
            &InvitationRejectedPayload {
                invitation_id: [9u8; 32],
                reason: RejectReason::Other,
            }
            .to_bytes(),
            3,
        );

        let unlocked_layout = SlotLayout::from_ledger(&ledger);
        assert_eq!(
            unlocked_layout.state_at(SlotIndex::new(0).unwrap()),
            SlotState::Occupied(StarterId::from([1u8; 32]))
        );
    }

    #[test]
    fn ignores_foreign_signed_invitation_for_slot_locking() {
        let owner = PubKey::from([7u8; 32]);
        let peer = PubKey::from([8u8; 32]);
        let mut ledger = Ledger::new(owner);

        append_event(
            &mut ledger,
            EventKind::StarterCreated,
            &starter_created(1, StarterKind::Juice),
            1,
        );
        append_event_with_signer(
            &mut ledger,
            EventKind::InvitationSent,
            &InvitationSentPayload {
                invitation_id: [9u8; 32],
                starter_id: StarterId::from([42u8; 32]),
                to_pubkey: owner,
            }
            .to_bytes(),
            2,
            peer,
        );

        let layout = SlotLayout::from_ledger(&ledger);
        assert_eq!(
            layout.state_at(SlotIndex::new(0).unwrap()),
            SlotState::Occupied(StarterId::from([1u8; 32]))
        );
        assert_eq!(layout.find_first_empty(), SlotIndex::new(1));
    }
}
