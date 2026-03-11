use super::*;
use hivra_core::event_payloads::RelationshipEstablishedPayload;
use std::sync::Mutex;

static TEST_GUARD: Mutex<()> = Mutex::new(());

fn test_seed(byte: u8) -> Seed {
    Seed([byte; 32])
}

fn derived_pubkey(seed: &Seed) -> PubKey {
    PubKey::from(derive_nostr_public_key(seed).unwrap())
}

fn set_runtime_capsule(owner: PubKey, network: Network) {
    let capsule = Capsule {
        pubkey: owner,
        capsule_type: CapsuleType::Leaf,
        network,
        ledger: Ledger::new(owner),
    };

    let mut runtime = RUNTIME.lock().unwrap();
    runtime.capsule = Some(capsule);
}

fn runtime_events() -> Vec<Event> {
    let runtime = RUNTIME.lock().unwrap();
    runtime.capsule.as_ref().unwrap().ledger.events().to_vec()
}

fn append_invitation_sent_for_test(
    invitation_id: [u8; 32],
    starter_id: [u8; 32],
    to_pubkey: [u8; 32],
    starter_slot: Option<u8>,
    from_pubkey: Option<[u8; 32]>,
) {
    let payload = InvitationSentPayload {
        invitation_id,
        starter_id: StarterId::from(starter_id),
        to_pubkey: PubKey::from(to_pubkey),
    };

    let mut bytes = payload.to_bytes();
    if let Some(slot) = starter_slot {
        bytes.push(slot);
    }
    if let Some(from) = from_pubkey {
        append_runtime_event_with_signer(EventKind::InvitationSent, &bytes, PubKey::from(from))
            .unwrap();
    } else {
        append_runtime_event(EventKind::InvitationSent, &bytes).unwrap();
    }
}

#[test]
fn finalize_local_acceptance_creates_starter_and_relationship() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let seed = test_seed(7);
    let local_pubkey = derived_pubkey(&seed);
    let inviter_pubkey = [3u8; 32];
    let invitation_id = [5u8; 32];
    let inviter_slot = 1u8;
    let peer_starter_id = derive_starter_id(&test_seed(11), inviter_slot);

    set_runtime_capsule(local_pubkey, Network::Neste);

    append_invitation_sent_for_test(
        invitation_id,
        peer_starter_id,
        local_pubkey.as_bytes().to_owned(),
        Some(inviter_slot),
        Some(inviter_pubkey),
    );

    let engine = build_engine(&seed);
    let acceptance_plan = resolve_local_acceptance_plan(&seed, invitation_id).unwrap();
    let created_starter_id = *acceptance_plan.relationship_starter_id.as_bytes();
    finalize_local_acceptance(&engine, &acceptance_plan, inviter_pubkey).unwrap();

    let events = runtime_events();
    assert!(events.iter().any(|event| {
        event.kind() == EventKind::StarterCreated
            && StarterCreatedPayload::from_bytes(event.payload())
                .is_ok_and(|payload| payload.starter_id.as_bytes() == &created_starter_id)
    }));
    assert!(events.iter().any(|event| {
        event.kind() == EventKind::RelationshipEstablished
            && RelationshipEstablishedPayload::from_bytes(event.payload()).is_ok_and(|payload| {
                payload.peer_pubkey == PubKey::from(inviter_pubkey)
                    && payload.own_starter_id.as_bytes() == &created_starter_id
                    && payload.peer_starter_id.as_bytes() == &peer_starter_id
                    && payload.kind == StarterKind::Spark
            })
    }));
}

#[test]
fn incoming_invitation_accepted_projects_outgoing_relationship() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(12);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [8u8; 32];
    let invitation_id = [4u8; 32];
    let own_starter_id = derive_starter_id(&test_seed(12), 0);
    let peer_starter_id = derive_starter_id(&test_seed(13), 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    let payload = InvitationAcceptedPayload {
        invitation_id,
        from_pubkey: local_pubkey,
        created_starter_id: StarterId::from(peer_starter_id),
    };

    let engine = build_engine(&local_seed);
    project_relationship_from_invitation_accepted(&engine, peer_pubkey, &payload).unwrap();

    let events = runtime_events();
    assert!(events.iter().any(|event| {
        event.kind() == EventKind::RelationshipEstablished
            && RelationshipEstablishedPayload::from_bytes(event.payload()).is_ok_and(|projected| {
                projected.peer_pubkey == PubKey::from(peer_pubkey)
                    && projected.own_starter_id.as_bytes() == &own_starter_id
                    && projected.peer_starter_id.as_bytes() == &peer_starter_id
                    && projected.kind == StarterKind::Juice
            })
    }));
}

#[test]
fn incoming_empty_slot_reject_burns_sender_starter() {
    let _guard = TEST_GUARD.lock().unwrap();
    clear_runtime_state();

    let local_seed = test_seed(21);
    let local_pubkey = derived_pubkey(&local_seed);
    let peer_pubkey = [8u8; 32];
    let invitation_id = [4u8; 32];
    let own_starter_id = derive_starter_id(&local_seed, 0);

    set_runtime_capsule(local_pubkey, Network::Neste);
    append_invitation_sent_for_test(invitation_id, own_starter_id, peer_pubkey, Some(0), None);

    let engine = build_engine(&local_seed);
    project_effects_from_invitation_rejected(
        &engine,
        &InvitationRejectedPayload {
            invitation_id,
            reason: RejectReason::EmptySlot,
        },
    )
    .unwrap();

    let events = runtime_events();
    assert!(events.iter().any(|event| {
        event.kind() == EventKind::StarterBurned
            && StarterBurnedPayload::from_bytes(event.payload()).is_ok_and(|payload| {
                payload.starter_id.as_bytes() == &own_starter_id
                    && payload.reason == RejectReason::EmptySlot as u8
            })
    }));
}
