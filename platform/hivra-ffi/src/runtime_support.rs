use super::*;

#[derive(Default)]
pub(crate) struct RuntimeState {
    pub(crate) capsule: Option<Capsule>,
}

pub(crate) struct FfiTimeSource;

impl TimeSource for FfiTimeSource {
    fn now(&self) -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0)
    }
}

pub(crate) struct FfiRandomSource;

impl RandomSource for FfiRandomSource {
    fn fill_bytes(&self, buf: &mut [u8]) {
        rand::thread_rng().fill_bytes(buf);
    }
}

pub(crate) struct SeedBackedKeyStore {
    pub(crate) seed: Seed,
}

impl SecureKeyStore for SeedBackedKeyStore {
    type Error = ();

    fn generate(&self) -> Result<[u8; 32], Self::Error> {
        derive_nostr_public_key(&self.seed).map_err(|_| ())
    }

    fn public_key(&self) -> Result<[u8; 32], Self::Error> {
        derive_nostr_public_key(&self.seed).map_err(|_| ())
    }

    fn sign(&self, msg: &[u8]) -> Result<[u8; 64], Self::Error> {
        let privkey = derive_nostr_keypair(&self.seed).map_err(|_| ())?;
        let crypto = NostrCryptoProvider::new();
        crypto.sign(msg, &privkey).map_err(|_| ())
    }
}

pub(crate) static RUNTIME: Lazy<Mutex<RuntimeState>> =
    Lazy::new(|| Mutex::new(RuntimeState::default()));

pub(crate) type FfiEngine =
    Engine<FfiTimeSource, FfiRandomSource, NostrCryptoProvider, SeedBackedKeyStore>;

pub(crate) fn build_engine(seed: &Seed) -> FfiEngine {
    Engine::new(
        FfiTimeSource,
        FfiRandomSource,
        NostrCryptoProvider::new(),
        SeedBackedKeyStore { seed: seed.clone() },
        EngineConfig::default(),
    )
}

pub(crate) fn derive_starter_id(seed: &Seed, slot: u8) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(seed.as_bytes());
    hasher.update([slot]);
    hasher.update(b"starter_v1");
    let digest = hasher.finalize();
    let mut out = [0u8; 32];
    out.copy_from_slice(&digest);
    out
}

pub(crate) fn derive_starter_nonce(seed: &Seed, slot: u8) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(seed.as_bytes());
    hasher.update([slot]);
    hasher.update(b"starter_nonce_v1");
    let digest = hasher.finalize();
    let mut out = [0u8; 32];
    out.copy_from_slice(&digest);
    out
}

pub(crate) fn derive_nostr_public_key(seed: &Seed) -> Result<[u8; 32], ()> {
    let secret_bytes = derive_nostr_keypair(seed).map_err(|_| ())?;
    let secret = SecretKey::from_slice(&secret_bytes).map_err(|_| ())?;
    let keys = Keys::new(secret);
    Ok(keys.public_key().to_bytes())
}

pub(crate) fn init_runtime_state(
    seed: &Seed,
    network: Network,
    capsule_type: CapsuleType,
) -> Result<(), &'static str> {
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

pub(crate) fn clear_runtime_state() {
    let mut runtime = RUNTIME.lock().unwrap();
    runtime.capsule = None;
}

pub(crate) fn current_capsule_state() -> Option<CapsuleState> {
    let runtime = RUNTIME.lock().unwrap();
    runtime.capsule.as_ref().map(CapsuleState::from_capsule)
}

pub(crate) fn export_runtime_ledger() -> Result<String, &'static str> {
    let runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_ref().ok_or("no capsule")?;
    let mut value = serde_json::to_value(&capsule.ledger).map_err(|_| "serialization failed")?;
    if let serde_json::Value::Object(map) = &mut value {
        map.insert(
            "last_hash".to_string(),
            serde_json::Value::String(capsule.ledger.last_hash().to_string()),
        );
    }
    serde_json::to_string(&value).map_err(|_| "serialization failed")
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
                map.insert(
                    "last_hash".to_string(),
                    serde_json::Value::Number(num.into()),
                );
            }
        }
    }
}

pub(crate) fn import_runtime_ledger(json: &str) -> Result<(), &'static str> {
    let mut runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_mut().ok_or("no capsule")?;

    let parsed: Ledger = match serde_json::from_str::<Ledger>(json) {
        Ok(ledger) => ledger,
        Err(_) => {
            let mut value: serde_json::Value =
                serde_json::from_str(json).map_err(|_| "parse failed")?;
            if let serde_json::Value::Object(obj) = &mut value {
                let schema = obj.get("schema").and_then(|v| v.as_str());
                let version = obj.get("version").and_then(|v| v.as_u64());
                if schema == Some("hivra.capsule_backup") && version == Some(1) {
                    if let Some(ledger_value) = obj.get_mut("ledger") {
                        normalize_ledger_last_hash(ledger_value);
                        serde_json::from_value(std::mem::take(ledger_value))
                            .map_err(|_| "parse failed")?
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

pub(crate) fn event_kind_from_u8(kind: u8) -> Option<EventKind> {
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

pub(crate) fn append_runtime_event_with_signer(
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

    let next_ts = core::cmp::max(now_ms, last_plus_one);

    let event = Event::new(
        kind,
        payload.to_vec(),
        Timestamp::from(next_ts),
        Signature::from([0u8; 64]),
        signer,
    );

    capsule.ledger.append(event).map_err(|_| "append failed")
}

pub(crate) fn append_runtime_event(kind: EventKind, payload: &[u8]) -> Result<(), &'static str> {
    let runtime = RUNTIME.lock().unwrap();
    let signer = runtime.capsule.as_ref().ok_or("no capsule")?.pubkey;
    drop(runtime);
    append_runtime_event_with_signer(kind, payload, signer)
}

pub(crate) fn append_prepared_event(prepared: PreparedEvent) -> Result<(), &'static str> {
    let mut runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_mut().ok_or("no capsule")?;
    capsule
        .ledger
        .append(prepared.event)
        .map_err(|_| "append failed")
}

pub(crate) fn event_exists_in_runtime(kind: EventKind, payload: &[u8]) -> bool {
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

pub(crate) fn event_exists_in_runtime_with_signer(
    kind: EventKind,
    payload: &[u8],
    signer: PubKey,
) -> bool {
    let runtime = RUNTIME.lock().unwrap();
    let Some(capsule) = runtime.capsule.as_ref() else {
        return false;
    };

    capsule.ledger.events().iter().any(|event| {
        event.kind() == kind && event.payload() == payload && event.signer() == &signer
    })
}

pub(crate) fn starter_kind_from_slot(slot: u8) -> Option<StarterKind> {
    match slot {
        0 => Some(StarterKind::Juice),
        1 => Some(StarterKind::Spark),
        2 => Some(StarterKind::Seed),
        3 => Some(StarterKind::Pulse),
        4 => Some(StarterKind::Kick),
        _ => None,
    }
}

pub(crate) fn capsule_network() -> Result<Network, &'static str> {
    let runtime = RUNTIME.lock().unwrap();
    Ok(runtime.capsule.as_ref().ok_or("no capsule")?.network)
}

pub(crate) fn find_starter_kind_by_id_in_runtime(starter_id: &[u8; 32]) -> Option<StarterKind> {
    let runtime = RUNTIME.lock().unwrap();
    let capsule = runtime.capsule.as_ref()?;

    for event in capsule.ledger.events() {
        if event.kind() != EventKind::StarterCreated {
            continue;
        }

        let Ok(payload) = StarterCreatedPayload::from_bytes(event.payload()) else {
            continue;
        };

        if payload.starter_id.as_bytes() == starter_id {
            return Some(payload.kind);
        }
    }

    None
}
