use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::ptr;
use std::sync::Mutex;

use futures::executor::block_on;
use hivra_core::{
    capsule::{Capsule, CapsuleState, CapsuleType},
    event::{Event, EventKind},
    event_payloads::{
        CapsuleCreatedPayload, EventPayload, InvitationAcceptedPayload, InvitationExpiredPayload,
        InvitationRejectedPayload, InvitationSentPayload, RejectReason, StarterBurnedPayload,
        StarterCreatedPayload,
    },
    Ledger, Network, PubKey, Signature, StarterId, StarterKind, Timestamp,
};
use hivra_engine::CryptoProvider;
use hivra_keystore::{
    delete_seed, derive_nostr_keypair, load_seed, mnemonic_to_seed, seed_exists, seed_to_mnemonic,
    store_seed, Seed,
};
use hivra_nostr_crypto::NostrCryptoProvider;
use hivra_transport::nostr::{NostrConfig, NostrTransport};
use hivra_transport::{Message, Transport, TransportError};
use nostr_sdk::prelude::{Keys, SecretKey};
use once_cell::sync::Lazy;
use rand::RngCore;
use serde::Deserialize;
use serde_json;
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Default)]
struct RuntimeState {
    capsule: Option<Capsule>,
}

static RUNTIME: Lazy<Mutex<RuntimeState>> = Lazy::new(|| Mutex::new(RuntimeState::default()));

fn derive_starter_id(seed: &Seed, slot: u8) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(seed.as_bytes());
    hasher.update([slot]);
    hasher.update(b"starter_v1");
    let digest = hasher.finalize();
    let mut out = [0u8; 32];
    out.copy_from_slice(&digest);
    out
}

fn derive_starter_nonce(seed: &Seed, slot: u8) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(seed.as_bytes());
    hasher.update([slot]);
    hasher.update(b"starter_nonce_v1");
    let digest = hasher.finalize();
    let mut out = [0u8; 32];
    out.copy_from_slice(&digest);
    out
}

fn derive_nostr_public_key(seed: &Seed) -> Result<[u8; 32], ()> {
    let secret_bytes = derive_nostr_keypair(seed).map_err(|_| ())?;
    let secret = SecretKey::from_slice(&secret_bytes).map_err(|_| ())?;
    let keys = Keys::new(secret);
    Ok(keys.public_key().to_bytes())
}

fn init_runtime_state(seed: &Seed, network: Network, capsule_type: CapsuleType) -> Result<(), &'static str> {
    let owner_bytes = derive_nostr_public_key(seed).map_err(|_| "failed to derive pubkey")?;
    let owner = PubKey::from(owner_bytes);
    let mut ledger = Ledger::new(owner);

    let payload = CapsuleCreatedPayload::new(network.to_byte(), capsule_type as u8, [0u8; 32]);
    let event = Event::new(
        EventKind::CapsuleCreated,
        payload.to_bytes(),
        Timestamp::from(0),
        Signature::from([0u8; 64]),
        owner,
    );
    let _ = ledger.append(event);

    // In current Flutter flow, Relay maps to Genesis and Leaf maps to Proto.
    if capsule_type == CapsuleType::Relay {
        let starter_kinds = [
            StarterKind::Juice,
            StarterKind::Spark,
            StarterKind::Seed,
            StarterKind::Pulse,
            StarterKind::Kick,
        ];

        for (slot, kind) in starter_kinds.iter().enumerate() {
            let slot_u8 = slot as u8;
            let starter_id = StarterId::from(derive_starter_id(seed, slot_u8));
            let nonce = derive_starter_nonce(seed, slot_u8);
            let payload = StarterCreatedPayload {
                starter_id,
                nonce,
                kind: *kind,
                network: network.to_byte(),
            };
            let starter_event = Event::new(
                EventKind::StarterCreated,
                payload.to_bytes(),
                Timestamp::from(slot as u64 + 1),
                Signature::from([0u8; 64]),
                owner,
            );
            let _ = ledger.append(starter_event);
        }
    }

    let capsule = Capsule {
        pubkey: owner,
        capsule_type,
        network,
        ledger,
    };

    let mut runtime = RUNTIME.lock().unwrap();
    runtime.capsule = Some(capsule);
    Ok(())
}

fn clear_runtime_state() {
    let mut runtime = RUNTIME.lock().unwrap();
    runtime.capsule = None;
}

fn current_capsule_state() -> Option<CapsuleState> {
    let runtime = RUNTIME.lock().unwrap();
    runtime.capsule.as_ref().map(|capsule| CapsuleState::from_capsule(capsule))
}

fn export_runtime_ledger() -> Result<String, &'static str> {
    let runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_ref().ok_or("no capsule")?;
    let mut value =
        serde_json::to_value(&capsule.ledger).map_err(|_| "serialization failed")?;
    if let serde_json::Value::Object(map) = &mut value {
        map.insert(
            "last_hash".to_string(),
            serde_json::Value::String(capsule.ledger.last_hash().to_string()),
        );
    }
    serde_json::to_string(&value).map_err(|_| "serialization failed")
}

#[derive(Deserialize)]
struct LedgerBackupEnvelopeV1 {
    schema: String,
    version: u32,
    ledger: Ledger,
}

fn normalize_ledger_last_hash(value: &mut serde_json::Value) {
    if let serde_json::Value::Object(map) = value {
        if let Some(raw) = map.get("last_hash") {
            let parsed = match raw {
                serde_json::Value::String(text) => {
                    let trimmed = text.trim();
                    if trimmed.starts_with("0x") || trimmed.starts_with("0X") {
                        u64::from_str_radix(&trimmed[2..], 16).ok()
                    } else {
                        trimmed.parse::<u64>().ok()
                    }
                }
                serde_json::Value::Number(num) => {
                    if let Some(v) = num.as_u64() {
                        Some(v)
                    } else {
                        num.as_f64().and_then(|v| {
                            if v.is_finite() && v >= 0.0 && v <= u64::MAX as f64 {
                                Some(v as u64)
                            } else {
                                None
                            }
                        })
                    }
                }
                _ => None,
            };

            if let Some(num) = parsed {
                map.insert("last_hash".to_string(), serde_json::Value::Number(num.into()));
            }
        }
    }
}

fn import_runtime_ledger(json: &str) -> Result<(), &'static str> {
    let mut runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_mut().ok_or("no capsule")?;

    let parsed: Ledger = match serde_json::from_str::<Ledger>(json) {
        Ok(ledger) => ledger,
        Err(_) => {
            let mut value: serde_json::Value = serde_json::from_str(json).map_err(|_| "parse failed")?;
            if let serde_json::Value::Object(obj) = &mut value {
                let schema = obj.get("schema").and_then(|v| v.as_str());
                let version = obj.get("version").and_then(|v| v.as_u64());
                if schema == Some("hivra.capsule_backup") && version == Some(1) {
                    if let Some(ledger_value) = obj.get_mut("ledger") {
                        normalize_ledger_last_hash(ledger_value);
                        let ledger: Ledger = serde_json::from_value(std::mem::take(ledger_value))
                            .map_err(|_| "parse failed")?;
                        ledger
                    } else {
                        return Err("parse failed");
                    }
                } else {
                    normalize_ledger_last_hash(&mut value);
                    serde_json::from_value(value).map_err(|_| "parse failed")?
                }
            } else {
                return Err("parse failed");
            }
        }
    };

    if parsed.owner() != &capsule.pubkey {
        return Err("owner mismatch");
    }
    capsule.ledger = parsed;
    Ok(())
}

fn event_kind_from_u8(kind: u8) -> Option<EventKind> {
    match kind {
        0 => Some(EventKind::CapsuleCreated),
        1 => Some(EventKind::InvitationSent),
        2 => Some(EventKind::InvitationAccepted),
        3 => Some(EventKind::InvitationRejected),
        4 => Some(EventKind::InvitationExpired),
        5 => Some(EventKind::StarterCreated),
        6 => Some(EventKind::StarterBurned),
        7 => Some(EventKind::RelationshipEstablished),
        8 => Some(EventKind::RelationshipBroken),
        _ => None,
    }
}

fn append_runtime_event_with_signer(
    kind: EventKind,
    payload: &[u8],
    signer: PubKey,
) -> Result<(), &'static str> {
    let mut runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_mut().ok_or("no capsule")?;

    let last_plus_one = capsule
        .ledger
        .events()
        .last()
        .map(|event| event.timestamp().as_u64().saturating_add(1))
        .unwrap_or(0);

    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(last_plus_one);

    // Keep monotonic ordering while moving to unix_ms UTC timestamps.
    let next_ts = core::cmp::max(now_ms, last_plus_one);

    let event = Event::new(
        kind,
        payload.to_vec(),
        Timestamp::from(next_ts),
        Signature::from([0u8; 64]),
        signer,
    );

    capsule
        .ledger
        .append(event)
        .map_err(|_| "append failed")
}

fn append_runtime_event(kind: EventKind, payload: &[u8]) -> Result<(), &'static str> {
    let runtime = RUNTIME.lock().unwrap();
    let signer = runtime.capsule.as_ref().ok_or("no capsule")?.pubkey;
    drop(runtime);
    append_runtime_event_with_signer(kind, payload, signer)
}

fn event_exists_in_runtime(kind: EventKind, payload: &[u8]) -> bool {
    let runtime = RUNTIME.lock().unwrap();
    let Some(capsule) = runtime.capsule.as_ref() else {
        return false;
    };

    capsule
        .ledger
        .events()
        .iter()
        .any(|event| event.kind() == kind && event.payload() == payload)
}

/// Structure for returning serialized bytes
#[repr(C)]
pub struct FfiBytes {
    data: *mut u8,
    len: usize,
}

// ============ SEED & MNEMONIC FUNCTIONS ============

/// Convert seed to mnemonic phrase (12 or 24 words)
#[no_mangle]
pub unsafe extern "C" fn hivra_seed_to_mnemonic(
    seed_ptr: *const u8,
    word_count: u32,
    out_phrase: *mut *mut c_char,
) -> i32 {
    if seed_ptr.is_null() || out_phrase.is_null() {
        return -1;
    }
    
    let seed_bytes = std::slice::from_raw_parts(seed_ptr, 32);
    let mut seed_array = [0u8; 32];
    seed_array.copy_from_slice(seed_bytes);
    let seed = Seed(seed_array);
    
    match seed_to_mnemonic(&seed, word_count as usize) {
        Ok(phrase) => {
            let c_str = CString::new(phrase).unwrap();
            *out_phrase = c_str.into_raw();
            0
        }
        Err(_) => -1,
    }
}

/// Convert mnemonic phrase to seed
#[no_mangle]
pub unsafe extern "C" fn hivra_mnemonic_to_seed(
    phrase_ptr: *const c_char,
    out_seed: *mut u8,
) -> i32 {
    if phrase_ptr.is_null() || out_seed.is_null() {
        return -1;
    }
    
    let phrase = match CStr::from_ptr(phrase_ptr).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };
    
    match mnemonic_to_seed(phrase) {
        Ok(seed) => {
            let seed_ref: &Seed = &seed;
            let seed_bytes: &[u8; 32] = seed_ref.as_bytes();
            std::ptr::copy_nonoverlapping(seed_bytes.as_ptr(), out_seed, 32);
            0
        }
        Err(_) => -1,
    }
}

/// Generate random 32-byte seed using OS RNG
#[no_mangle]
pub unsafe extern "C" fn hivra_generate_random_seed(out_seed: *mut u8) -> i32 {
    if out_seed.is_null() {
        return -1;
    }
    
    let mut rng = rand::thread_rng();
    let mut seed = [0u8; 32];
    rng.fill_bytes(&mut seed);
    
    std::ptr::copy_nonoverlapping(seed.as_ptr(), out_seed, 32);
    0
}

/// Free string allocated by FFI
#[no_mangle]
pub unsafe extern "C" fn hivra_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

// ============ KEYCHAIN FUNCTIONS ============

/// Check if seed exists in keystore
#[no_mangle]
pub unsafe extern "C" fn hivra_seed_exists() -> i8 {
    seed_exists() as i8
}

/// Save seed to keystore
#[no_mangle]
pub unsafe extern "C" fn hivra_seed_save(seed_ptr: *const u8) -> i32 {
    if seed_ptr.is_null() {
        return -1;
    }
    
    let seed_bytes = std::slice::from_raw_parts(seed_ptr, 32);
    let mut seed_array = [0u8; 32];
    seed_array.copy_from_slice(seed_bytes);
    let seed = Seed(seed_array);
    
    match store_seed(&seed) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// Load seed from keystore
#[no_mangle]
pub unsafe extern "C" fn hivra_seed_load(out_seed: *mut u8) -> i32 {
    if out_seed.is_null() {
        return -1;
    }
    
    match load_seed() {
        Ok(seed) => {
            let seed_ref: &Seed = &seed;
            let seed_bytes: &[u8; 32] = seed_ref.as_bytes();
            std::ptr::copy_nonoverlapping(seed_bytes.as_ptr(), out_seed, 32);
            0
        }
        Err(_) => -1,
    }
}

/// Delete seed from keystore
#[no_mangle]
pub unsafe extern "C" fn hivra_seed_delete() -> i32 {
    match delete_seed() {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

// ============ CAPSULE FUNCTIONS ============

/// Create a new capsule from seed
#[no_mangle]
pub unsafe extern "C" fn hivra_capsule_create(
    seed_ptr: *const u8,
    _network: u8,
    _capsule_type: u8,
) -> i32 {
    if seed_ptr.is_null() {
        return -1;
    }
    
    let seed_bytes = std::slice::from_raw_parts(seed_ptr, 32);
    let mut seed_array = [0u8; 32];
    seed_array.copy_from_slice(seed_bytes);
    let seed = Seed(seed_array);
    
    let network = if _network == 0 { Network::Hood } else { Network::Neste };
    let capsule_type = if _capsule_type == 1 {
        CapsuleType::Relay
    } else {
        CapsuleType::Leaf
    };

    match store_seed(&seed) {
        Ok(_) => {
            if init_runtime_state(&seed, network, capsule_type).is_err() {
                return -2;
            }
            0
        }
        Err(_) => -1,
    }
}

/// Get capsule public key (derived from seed)
#[no_mangle]
pub unsafe extern "C" fn hivra_capsule_public_key(out_key: *mut u8) -> i32 {
    if out_key.is_null() {
        return -1;
    }
    
    match load_seed() {
        Ok(seed) => {
            match derive_nostr_public_key(&seed) {
                Ok(pubkey) => {
                    let pubkey_array: [u8; 32] = pubkey;
                    std::ptr::copy_nonoverlapping(pubkey_array.as_ptr(), out_key, 32);
                    0
                }
                Err(_) => -1,
            }
        }
        Err(_) => -1,
    }
}

/// Reset capsule (delete seed and ledger)
#[no_mangle]
pub unsafe extern "C" fn hivra_capsule_reset() -> i32 {
    match delete_seed() {
        Ok(_) => {
            clear_runtime_state();
            0
        }
        Err(_) => -1,
    }
}

// ============ STARTER FUNCTIONS ============

/// Get starter ID for a slot (deterministic from seed)
#[no_mangle]
pub unsafe extern "C" fn hivra_starter_get_id(slot: u8, out_id: *mut u8) -> i32 {
    if out_id.is_null() || slot >= 5 {
        return -1;
    }
    
    match load_seed() {
        Ok(seed) => {
            let seed_ref: &Seed = &seed;
            let mut hasher = Sha256::new();
            hasher.update(seed_ref.as_bytes());
            hasher.update(&[slot]);
            hasher.update(b"starter_v1");
            let result = hasher.finalize();
            
            std::ptr::copy_nonoverlapping(result.as_ptr(), out_id, 32);
            0
        }
        Err(_) => -1,
    }
}

/// Get starter type for a slot (Juice, Spark, Seed, Pulse, Kick)
#[no_mangle]
pub unsafe extern "C" fn hivra_starter_get_type(slot: u8) -> i32 {
    if slot >= 5 {
        return -1;
    }
    slot as i32
}

/// Check if starter exists in slot
#[no_mangle]
pub unsafe extern "C" fn hivra_starter_exists(slot: u8) -> i8 {
    if slot >= 5 {
        return 0;
    }

    let runtime = RUNTIME.lock().unwrap();
    let capsule = match runtime.capsule.as_ref() {
        Some(capsule) => capsule,
        None => return 0,
    };

    let mut by_kind: [Option<[u8; 32]>; 5] = [None, None, None, None, None];

    for event in capsule.ledger.events() {
        match event.kind() {
            EventKind::StarterCreated => {
                if let Ok(payload) = StarterCreatedPayload::from_bytes(event.payload()) {
                    let kind_idx = payload.kind as usize;
                    if kind_idx < by_kind.len() {
                        by_kind[kind_idx] = Some(*payload.starter_id.as_bytes());
                    }
                }
            }
            EventKind::StarterBurned => {
                if let Ok(payload) = StarterBurnedPayload::from_bytes(event.payload()) {
                    let burned = *payload.starter_id.as_bytes();
                    for slot_ref in by_kind.iter_mut() {
                        if slot_ref.as_ref().is_some_and(|id| *id == burned) {
                            *slot_ref = None;
                        }
                    }
                }
            }
            _ => {}
        }
    }

    if by_kind[slot as usize].is_some() { 1 } else { 0 }
}

/// Send invitation through transport and append InvitationSent to local ledger.
///
/// Returns:
/// - 0 on success
/// - negative value on failure
#[no_mangle]
pub unsafe extern "C" fn hivra_send_invitation(to_pubkey_ptr: *const u8, starter_slot: u8) -> i32 {
    if to_pubkey_ptr.is_null() || starter_slot >= 5 {
        return -1;
    }

    let to_slice = std::slice::from_raw_parts(to_pubkey_ptr, 32);
    let mut to_pubkey = [0u8; 32];
    to_pubkey.copy_from_slice(to_slice);

    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -2,
    };

    let sender_secret = match derive_nostr_keypair(&seed) {
        Ok(key) => key,
        Err(_) => return -3,
    };

    let sender_pubkey = match derive_nostr_public_key(&seed) {
        Ok(key) => key,
        Err(_) => return -3,
    };

    {
        let runtime = RUNTIME.lock().unwrap();
        if runtime.capsule.is_none() {
            return -4;
        }
    }

    let transport = match NostrTransport::new(NostrConfig::default(), &sender_secret) {
        Ok(transport) => transport,
        Err(_) => return -5,
    };

    let starter_id = StarterId::from(derive_starter_id(&seed, starter_slot));
    let mut invitation_id = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut invitation_id);

    let payload = InvitationSentPayload {
        invitation_id,
        starter_id,
        to_pubkey: PubKey::from(to_pubkey),
    };
    let mut payload_bytes = payload.to_bytes();
    // Include starter kind byte so receiver can render correct kind for incoming invitation.
    payload_bytes.push(starter_slot);
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);

    let message = Message {
        from: sender_pubkey,
        to: to_pubkey,
        kind: EventKind::InvitationSent as u32,
        payload: payload_bytes.clone(),
        timestamp,
        invitation_id: Some(invitation_id),
    };

    if transport.send(message).is_err() {
        eprintln!("[Nostr] InvitationSent publish failed");
        return -7;
    }

    eprintln!("[Nostr] InvitationSent published");

    match append_runtime_event(EventKind::InvitationSent, &payload_bytes) {
        Ok(_) => 0,
        Err(_) => -6,
    }
}

/// Receive transport messages from relays and append supported events to local ledger.
///
/// Returns:
/// - >=0 number of newly appended events
/// - negative value on failure
#[no_mangle]
pub unsafe extern "C" fn hivra_transport_receive() -> i32 {
    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -1,
    };

    let local_pubkey = match derive_nostr_public_key(&seed) {
        Ok(key) => key,
        Err(_) => return -2,
    };

    let sender_secret = match derive_nostr_keypair(&seed) {
        Ok(key) => key,
        Err(_) => return -2,
    };

    {
        let runtime = RUNTIME.lock().unwrap();
        if runtime.capsule.is_none() {
            return -3;
        }
    }

    let transport = match NostrTransport::new(NostrConfig::default(), &sender_secret) {
        Ok(transport) => transport,
        Err(_) => return -4,
    };

    let received = match transport.receive() {
        Ok(messages) => messages,
        Err(_) => return -5,
    };

    let mut appended: i32 = 0;
    for message in received {
        eprintln!(
            "[Nostr] Received message kind={} payload_len={} to_prefix={:02x?}",
            message.kind,
            message.payload.len(),
            &message.to[..4]
        );

        let to_matches = message.to == local_pubkey;

        let kind_u8 = match u8::try_from(message.kind) {
            Ok(value) => value,
            Err(_) => {
                eprintln!("[Nostr] Skip message: unsupported kind value {}", message.kind);
                continue;
            }
        };

        let kind = match event_kind_from_u8(kind_u8) {
            Some(value) => value,
            None => {
                eprintln!("[Nostr] Skip message: unmapped kind {}", kind_u8);
                continue;
            }
        };

        // Fallback routing check by payload for InvitationSent in case `message.to` encoding differs.
        let payload_targets_local = if kind == EventKind::InvitationSent && message.payload.len() >= 96 {
            let mut to_from_payload = [0u8; 32];
            to_from_payload.copy_from_slice(&message.payload[64..96]);
            to_from_payload == local_pubkey
        } else {
            false
        };

        if !to_matches && !payload_targets_local {
            eprintln!("[Nostr] Skip message: not addressed to local capsule");
            continue;
        }

        // For incoming InvitationSent, keep original sender in local payload
        // so UI can route InvitationAccepted back to the inviter.
        // Supported wire payloads: 96 (legacy), 97 (legacy + kind byte).
        // Local persisted payloads become 128 or 129 respectively by appending from_pubkey.
        let local_payload = if kind == EventKind::InvitationSent
            && (message.payload.len() == 96 || message.payload.len() == 97)
        {
            let mut extended = message.payload.clone();
            extended.extend_from_slice(&message.from);
            extended
        } else {
            message.payload.clone()
        };

        if event_exists_in_runtime(kind, &local_payload) {
            eprintln!("[Nostr] Skip message: event already exists");
            continue;
        }

        match append_runtime_event(kind, &local_payload) {
            Ok(_) => {
                appended += 1;
            }
            Err(err) => {
                eprintln!("[Nostr] Skip message: append failed ({})", err);
            }
        }
    }

    appended
}

/// Send and append InvitationAccepted through transport + local ledger.
#[no_mangle]
pub unsafe extern "C" fn hivra_accept_invitation(
    invitation_id_ptr: *const u8,
    from_pubkey_ptr: *const u8,
    created_starter_id_ptr: *const u8,
) -> i32 {
    if invitation_id_ptr.is_null() || from_pubkey_ptr.is_null() || created_starter_id_ptr.is_null() {
        return -1;
    }

    let mut invitation_id = [0u8; 32];
    invitation_id.copy_from_slice(std::slice::from_raw_parts(invitation_id_ptr, 32));

    let mut from_pubkey = [0u8; 32];
    from_pubkey.copy_from_slice(std::slice::from_raw_parts(from_pubkey_ptr, 32));

    let mut created_starter_id = [0u8; 32];
    created_starter_id.copy_from_slice(std::slice::from_raw_parts(created_starter_id_ptr, 32));

    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -2,
    };

    let sender_secret = match derive_nostr_keypair(&seed) {
        Ok(key) => key,
        Err(_) => return -4,
    };

    let sender_pubkey = match derive_nostr_public_key(&seed) {
        Ok(key) => key,
        Err(_) => return -4,
    };

    {
        let runtime = RUNTIME.lock().unwrap();
        if runtime.capsule.is_none() {
            return -5;
        }
    }

    let payload = InvitationAcceptedPayload {
        invitation_id,
        from_pubkey: PubKey::from(from_pubkey),
        created_starter_id: StarterId::from(created_starter_id),
    };
    let payload_bytes = payload.to_bytes();

    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);

    let message = Message {
        from: sender_pubkey,
        to: from_pubkey,
        kind: EventKind::InvitationAccepted as u32,
        payload: payload_bytes.clone(),
        timestamp,
        invitation_id: Some(invitation_id),
    };

    eprintln!(
        "[Nostr] Sending InvitationAccepted to_prefix={:02x?} invitation_prefix={:02x?}",
        &from_pubkey[..4],
        &invitation_id[..4]
    );

    let transport = match NostrTransport::new(NostrConfig::default(), &sender_secret) {
        Ok(transport) => transport,
        Err(_) => return -6,
    };

    if transport.send(message).is_err() {
        return -7;
    }

    match append_runtime_event(EventKind::InvitationAccepted, &payload_bytes) {
        Ok(_) => 0,
        Err(_) => -3,
    }
}

/// Append InvitationRejected through Engine orchestration.
#[no_mangle]
pub unsafe extern "C" fn hivra_reject_invitation(
    invitation_id_ptr: *const u8,
    reason: u8,
) -> i32 {
    if invitation_id_ptr.is_null() {
        return -1;
    }

    let reject_reason = match reason {
        0 => RejectReason::EmptySlot,
        1 => RejectReason::Other,
        _ => return -2,
    };

    let mut invitation_id = [0u8; 32];
    invitation_id.copy_from_slice(std::slice::from_raw_parts(invitation_id_ptr, 32));

    let payload = InvitationRejectedPayload {
        invitation_id,
        reason: reject_reason,
    };

    match append_runtime_event(EventKind::InvitationRejected, &payload.to_bytes()) {
        Ok(_) => 0,
        Err(_) => -4,
    }
}

/// Append InvitationExpired through Engine orchestration.
#[no_mangle]
pub unsafe extern "C" fn hivra_expire_invitation(invitation_id_ptr: *const u8) -> i32 {
    if invitation_id_ptr.is_null() {
        return -1;
    }

    let mut invitation_id = [0u8; 32];
    invitation_id.copy_from_slice(std::slice::from_raw_parts(invitation_id_ptr, 32));

    let payload = InvitationExpiredPayload { invitation_id };
    match append_runtime_event(EventKind::InvitationExpired, &payload.to_bytes()) {
        Ok(_) => 0,
        Err(_) => -3,
    }
}

// ============ OUR NEW UNIFIED FUNCTION ============

/// Get complete capsule state in one FFI call
#[no_mangle]
pub unsafe extern "C" fn capsule_state_encode(_capsule_ptr: *const c_void) -> FfiBytes {
    if let Some(state) = current_capsule_state() {
        match bincode::serialize(&state) {
            Ok(bytes) => {
                let mut boxed = bytes.into_boxed_slice();
                let data = boxed.as_mut_ptr();
                let len = boxed.len();
                std::mem::forget(boxed);
                FfiBytes { data, len }
            }
            Err(_) => FfiBytes { data: ptr::null_mut(), len: 0 },
        }
    } else {
        FfiBytes { data: ptr::null_mut(), len: 0 }
    }
}

/// Export the current ledger as JSON
#[no_mangle]
pub unsafe extern "C" fn hivra_export_ledger(out_json: *mut *mut c_char) -> i32 {
    if out_json.is_null() {
        return -1;
    }

    match export_runtime_ledger() {
        Ok(json) => match CString::new(json) {
            Ok(cstr) => {
                *out_json = cstr.into_raw();
                0
            }
            Err(_) => -2,
        },
        Err(_) => -2,
    }
}

/// Import a ledger from JSON and replace the runtime ledger
#[no_mangle]
pub unsafe extern "C" fn hivra_import_ledger(json_ptr: *const c_char) -> i32 {
    if json_ptr.is_null() {
        return -1;
    }

    let json = match CStr::from_ptr(json_ptr).to_str() {
        Ok(v) => v,
        Err(_) => return -2,
    };

    match import_runtime_ledger(json) {
        Ok(_) => 0,
        Err(_) => -3,
    }
}

/// Append a domain event to the runtime ledger.
///
/// Returns:
/// - 0 on success
/// - negative value on failure
#[no_mangle]
pub unsafe extern "C" fn hivra_ledger_append_event(
    kind: u8,
    payload_ptr: *const u8,
    payload_len: usize,
) -> i32 {
    if payload_len > 0 && payload_ptr.is_null() {
        return -1;
    }

    let event_kind = match event_kind_from_u8(kind) {
        Some(value) => value,
        None => return -2,
    };

    let payload = if payload_len == 0 {
        &[][..]
    } else {
        std::slice::from_raw_parts(payload_ptr, payload_len)
    };

    match append_runtime_event(event_kind, payload) {
        Ok(_) => 0,
        Err(_) => -3,
    }
}

/// Basic crypto adapter self-check.
///
/// Returns:
/// - 0 on success
/// - negative value on failure
#[no_mangle]
pub unsafe extern "C" fn hivra_crypto_self_check() -> i32 {
    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -1,
    };

    let privkey = match derive_nostr_keypair(&seed) {
        Ok(key) => key,
        Err(_) => return -2,
    };

    let provider = NostrCryptoProvider::new();
    let msg = [0x42u8; 32];

    match provider.sign(&msg, &privkey) {
        Ok(_) => 0,
        Err(_) => -3,
    }
}

/// End-to-end self-check for the prepared-send path.
///
/// This validates the migration path where transport does not own signing.
///
/// Returns:
/// - 0 on success
/// - negative value on failure
#[no_mangle]
pub unsafe extern "C" fn hivra_nostr_send_prepared_self_check() -> i32 {
    let seed = match load_seed() {
        Ok(seed) => seed,
        Err(_) => return -1,
    };

    let privkey = match derive_nostr_keypair(&seed) {
        Ok(key) => key,
        Err(_) => return -2,
    };

    let transport = match NostrTransport::new(NostrConfig::default(), &privkey) {
        Ok(transport) => transport,
        Err(_) => return -3,
    };

    let signing_secret = match SecretKey::from_slice(&privkey) {
        Ok(secret) => secret,
        Err(_) => return -4,
    };
    let keys = Keys::new(signing_secret);

    let message = Message {
        from: transport.public_key_bytes(),
        to: transport.public_key_bytes(),
        kind: 1,
        payload: vec![1, 2, 3],
        timestamp: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0),
        invitation_id: None,
    };

    match transport.prepare_event(&message, |builder| {
        block_on(builder.sign(&keys)).map_err(|_| TransportError::EncodingFailed)
    }) {
        Ok(_) => 0,
        Err(_) => -5,
    }
}

/// Free memory allocated by capsule_state_encode
#[no_mangle]
pub unsafe extern "C" fn free_bytes(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        let _ = Vec::from_raw_parts(ptr, len, len);
    }
}
