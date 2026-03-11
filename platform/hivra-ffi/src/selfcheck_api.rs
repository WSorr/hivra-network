use super::*;

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
