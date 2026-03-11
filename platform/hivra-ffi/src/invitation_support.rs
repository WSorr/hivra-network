use super::*;

pub(crate) fn find_invitation_sent_in_runtime(
    invitation_id: &[u8; 32],
) -> Option<(StarterId, StarterKind, PubKey, bool)> {
    find_invitation_sent_in_runtime_with_direction(invitation_id, None)
}

pub(crate) fn find_invitation_sent_in_runtime_with_direction(
    invitation_id: &[u8; 32],
    expect_incoming: Option<bool>,
) -> Option<(StarterId, StarterKind, PubKey, bool)> {
    let runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_ref()?;
    let local_pubkey = capsule.pubkey;
    let mut fallback: Option<(StarterId, StarterKind, PubKey, bool)> = None;

    for event in capsule.ledger.events() {
        if event.kind() != EventKind::InvitationSent {
            continue;
        }

        let payload = event.payload();
        if payload.len() != 96 && payload.len() != 97 {
            continue;
        }

        let mut current_invitation_id = [0u8; 32];
        current_invitation_id.copy_from_slice(&payload[..32]);
        if current_invitation_id != *invitation_id {
            continue;
        }

        let mut starter_id = [0u8; 32];
        starter_id.copy_from_slice(&payload[32..64]);

        let mut addressed_to = [0u8; 32];
        addressed_to.copy_from_slice(&payload[64..96]);
        let signer = *event.signer().as_bytes();

        let is_incoming_by_signer_and_address = addressed_to == local_pubkey.as_bytes().to_owned()
            && signer != local_pubkey.as_bytes().to_owned();
        let is_incoming = is_incoming_by_signer_and_address;

        let mut peer_pubkey = [0u8; 32];
        if is_incoming {
            peer_pubkey.copy_from_slice(&signer);
        } else {
            peer_pubkey.copy_from_slice(&addressed_to);
        }

        let kind = if payload.len() == 97 {
            starter_kind_from_slot(payload[96]).unwrap_or(StarterKind::Juice)
        } else {
            find_starter_kind_by_id_in_runtime(&starter_id).unwrap_or(StarterKind::Juice)
        };

        let candidate = (
            StarterId::from(starter_id),
            kind,
            PubKey::from(peer_pubkey),
            is_incoming,
        );
        match expect_incoming {
            Some(expected) if expected == is_incoming => return Some(candidate),
            Some(_) => {
                if fallback.is_none() {
                    fallback = Some(candidate);
                }
            }
            None => return Some(candidate),
        }
    }

    fallback
}

pub(crate) fn debug_log_invitation_sent_candidates(label: &str, target_invitation_id: &[u8; 32]) {
    let runtime = RUNTIME.lock().unwrap();
    let Some(capsule) = runtime.capsule.as_ref() else {
        eprintln!("[InviteLookup] {} no capsule", label);
        return;
    };
    let local_pubkey = capsule.pubkey;

    eprintln!(
        "[InviteLookup] {} target={:02x?} local={:02x?}",
        label,
        &target_invitation_id[..4],
        &local_pubkey.as_bytes()[..4]
    );

    for event in capsule.ledger.events() {
        if event.kind() != EventKind::InvitationSent {
            continue;
        }

        let payload = event.payload();
        if payload.len() != 96 && payload.len() != 97 {
            continue;
        }

        let mut current_invitation_id = [0u8; 32];
        current_invitation_id.copy_from_slice(&payload[..32]);

        let mut addressed_to = [0u8; 32];
        addressed_to.copy_from_slice(&payload[64..96]);
        let signer = *event.signer().as_bytes();
        let is_incoming = addressed_to == local_pubkey.as_bytes().to_owned()
            && signer != local_pubkey.as_bytes().to_owned();

        eprintln!(
            "[InviteLookup] candidate id={:02x?} signer={:02x?} to={:02x?} incoming={} len={}",
            &current_invitation_id[..4],
            &signer[..4],
            &addressed_to[..4],
            is_incoming,
            payload.len()
        );
    }
}

fn append_starter_created_if_missing(
    engine: &FfiEngine,
    starter_id: StarterId,
    kind: StarterKind,
    network: Network,
    nonce: [u8; 32],
) -> Result<(), &'static str> {
    let prepared = engine
        .prepare_starter_created(starter_id, nonce, kind, network)
        .map_err(|_| "prepare failed")?;
    let payload_bytes = prepared.event.payload().to_vec();

    if event_exists_in_runtime(EventKind::StarterCreated, &payload_bytes) {
        return Ok(());
    }

    append_prepared_event(prepared)
}

fn append_relationship_established_if_missing(
    engine: &FfiEngine,
    peer_pubkey: PubKey,
    own_starter_id: StarterId,
    peer_starter_id: StarterId,
    kind: StarterKind,
) -> Result<(), &'static str> {
    let prepared = engine
        .prepare_relationship_established(peer_pubkey, own_starter_id, peer_starter_id, kind)
        .map_err(|_| "prepare failed")?;
    let payload_bytes = prepared.event.payload().to_vec();

    if event_exists_in_runtime(EventKind::RelationshipEstablished, &payload_bytes) {
        return Ok(());
    }

    append_prepared_event(prepared)
}

pub(crate) fn project_relationship_from_invitation_accepted(
    engine: &FfiEngine,
    message_from: [u8; 32],
    payload: &InvitationAcceptedPayload,
) -> Result<(), &'static str> {
    debug_log_invitation_sent_candidates("incoming_accept", &payload.invitation_id);
    let Some((own_starter_id, kind, _, false)) =
        find_invitation_sent_in_runtime_with_direction(&payload.invitation_id, Some(false))
    else {
        return Err("matching outgoing invitation not found");
    };

    let relationship = engine
        .prepare_relationship_established(
            PubKey::from(message_from),
            own_starter_id,
            payload.created_starter_id,
            kind,
        )
        .map_err(|_| "prepare failed")?;

    let effect = IncomingEffect::Append(relationship.event);
    let IncomingEffect::Append(event) = effect;
    append_prepared_event(PreparedEvent {
        event,
        recipient: None,
    })
}

pub(crate) fn project_effects_from_invitation_rejected(
    engine: &FfiEngine,
    payload: &InvitationRejectedPayload,
) -> Result<(), &'static str> {
    let Some((starter_id, _, _, false)) =
        find_invitation_sent_in_runtime_with_direction(&payload.invitation_id, Some(false))
    else {
        return Err("matching outgoing invitation not found");
    };

    match payload.reason {
        RejectReason::EmptySlot => {
            let prepared = engine
                .prepare_starter_burned(starter_id, payload.reason as u8)
                .map_err(|_| "prepare failed")?;

            if event_exists_in_runtime(EventKind::StarterBurned, prepared.event.payload()) {
                return Ok(());
            }

            append_prepared_event(prepared)
        }
        RejectReason::Other => Ok(()),
    }
}

pub(crate) struct LocalAcceptancePlan {
    pub(crate) relationship_starter_id: StarterId,
    pub(crate) relationship_kind: StarterKind,
    pub(crate) peer_starter_id: StarterId,
    pub(crate) created_starter: Option<(StarterId, StarterKind, [u8; 32])>,
}

pub(crate) fn resolve_local_acceptance_plan(
    seed: &Seed,
    invitation_id: [u8; 32],
) -> Result<LocalAcceptancePlan, &'static str> {
    let Some((peer_starter_id, invited_kind, _, true)) =
        find_invitation_sent_in_runtime_with_direction(&invitation_id, Some(true))
    else {
        eprintln!(
            "[Accept] resolve plan failed: invitation {:02x?} not found as incoming",
            &invitation_id[..4]
        );
        return Err("matching incoming invitation not found");
    };

    let runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_ref().ok_or("no capsule")?;
    let slots = hivra_core::slot::SlotLayout::from_ledger(&capsule.ledger);
    let plan = hivra_core::plan_accept_for_kind(&capsule.ledger, &slots, invited_kind);
    eprintln!(
        "[Accept] planning invitation={:02x?} invited_kind={:?} peer_starter={:02x?} slots={:?} plan={:?}",
        &invitation_id[..4],
        invited_kind,
        &peer_starter_id.as_bytes()[..4],
        slots.states(),
        plan
    );
    drop(runtime);

    match plan {
        hivra_core::AcceptPlan::UseExistingStarter {
            relationship_starter_id,
            created_starter,
        } => {
            let created_starter = created_starter.map(|planned| {
                let slot = planned.slot.as_u8();
                (
                    StarterId::from(derive_starter_id(seed, slot)),
                    planned.kind,
                    derive_starter_nonce(seed, slot),
                )
            });

            Ok(LocalAcceptancePlan {
                relationship_starter_id,
                relationship_kind: invited_kind,
                peer_starter_id,
                created_starter,
            })
        }
        hivra_core::AcceptPlan::CreateStarterInEmptySlot { slot, kind } => {
            Ok(LocalAcceptancePlan {
                relationship_starter_id: StarterId::from(derive_starter_id(seed, slot.as_u8())),
                relationship_kind: invited_kind,
                peer_starter_id,
                created_starter: Some((
                    StarterId::from(derive_starter_id(seed, slot.as_u8())),
                    kind,
                    derive_starter_nonce(seed, slot.as_u8()),
                )),
            })
        }
        hivra_core::AcceptPlan::NoCapacity => Err("no capacity to accept invitation"),
    }
}

pub(crate) fn finalize_local_acceptance(
    engine: &FfiEngine,
    plan: &LocalAcceptancePlan,
    from_pubkey: [u8; 32],
) -> Result<(), &'static str> {
    let network = capsule_network()?;
    eprintln!(
        "[Accept] finalize from={:02x?} relationship_starter={:02x?} peer_starter={:02x?} kind={:?} created={}",
        &from_pubkey[..4],
        &plan.relationship_starter_id.as_bytes()[..4],
        &plan.peer_starter_id.as_bytes()[..4],
        plan.relationship_kind,
        plan.created_starter.is_some()
    );

    if let Some((created_starter_id, created_kind, created_nonce)) = plan.created_starter {
        eprintln!(
            "[Accept] append StarterCreated starter={:02x?} kind={:?}",
            &created_starter_id.as_bytes()[..4],
            created_kind
        );
        append_starter_created_if_missing(
            engine,
            created_starter_id,
            created_kind,
            network,
            created_nonce,
        )?;
        eprintln!("[Accept] StarterCreated append ok");
    }

    eprintln!("[Accept] append RelationshipEstablished");
    append_relationship_established_if_missing(
        engine,
        PubKey::from(from_pubkey),
        plan.relationship_starter_id,
        plan.peer_starter_id,
        plan.relationship_kind,
    )?;
    eprintln!("[Accept] RelationshipEstablished append ok");
    Ok(())
}
