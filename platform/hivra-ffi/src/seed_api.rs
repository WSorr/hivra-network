use super::*;

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
