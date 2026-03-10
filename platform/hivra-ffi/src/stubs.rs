use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

// Stub for seed to mnemonic conversion
#[no_mangle]
pub unsafe extern "C" fn hivra_seed_to_mnemonic(
    seed: *const u8,
    word_count: u32,
    out_phrase: *mut *mut c_char,
) -> i32 {
    if seed.is_null() || out_phrase.is_null() {
        return -1;
    }
    
    // Return a dummy mnemonic
    let dummy = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art";
    let c_str = CString::new(dummy).unwrap();
    *out_phrase = c_str.into_raw();
    0
}

#[no_mangle]
pub unsafe extern "C" fn hivra_mnemonic_to_seed(
    phrase: *const c_char,
    out_seed: *mut u8,
) -> i32 {
    if phrase.is_null() || out_seed.is_null() {
        return -1;
    }
    
    // Return dummy seed (all zeros)
    let seed = [0u8; 32];
    std::ptr::copy_nonoverlapping(seed.as_ptr(), out_seed, 32);
    0
}

#[no_mangle]
pub unsafe extern "C" fn hivra_generate_random_seed(out_seed: *mut u8) -> i32 {
    if out_seed.is_null() {
        return -1;
    }
    
    // Return deterministic seed for testing
    let seed = [
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
        0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20,
    ];
    std::ptr::copy_nonoverlapping(seed.as_ptr(), out_seed, 32);
    0
}

#[no_mangle]
pub unsafe extern "C" fn hivra_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

#[no_mangle]
pub unsafe extern "C" fn hivra_seed_exists() -> i8 {
    1 // Return true (seed exists)
}

#[no_mangle]
pub unsafe extern "C" fn hivra_seed_save(seed: *const u8) -> i32 {
    if seed.is_null() {
        return -1;
    }
    0 // Success
}

#[no_mangle]
pub unsafe extern "C" fn hivra_seed_load(out_seed: *mut u8) -> i32 {
    if out_seed.is_null() {
        return -1;
    }
    
    // Load dummy seed
    let seed = [
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
        0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20,
    ];
    std::ptr::copy_nonoverlapping(seed.as_ptr(), out_seed, 32);
    0
}

#[no_mangle]
pub unsafe extern "C" fn hivra_seed_delete() -> i32 {
    0 // Success
}

#[no_mangle]
pub unsafe extern "C" fn hivra_capsule_create(
    seed: *const u8,
    network: u8,
    capsule_type: u8,
) -> i32 {
    if seed.is_null() {
        return -1;
    }
    0 // Success
}

#[no_mangle]
pub unsafe extern "C" fn hivra_capsule_public_key(out_key: *mut u8) -> i32 {
    if out_key.is_null() {
        return -1;
    }
    
    // Return dummy public key
    let key = [
        0xab, 0xcd, 0x12, 0x34, 0x56, 0x78, 0x90, 0xab,
        0xcd, 0xef, 0x12, 0x34, 0x56, 0x78, 0x90, 0xab,
        0xcd, 0xef, 0x12, 0x34, 0x56, 0x78, 0x90, 0xab,
        0xcd, 0xef, 0x12, 0x34, 0x56, 0x78, 0x90, 0xab,
    ];
    std::ptr::copy_nonoverlapping(key.as_ptr(), out_key, 32);
    0
}

#[no_mangle]
pub unsafe extern "C" fn hivra_capsule_reset() -> i32 {
    0 // Success
}

#[no_mangle]
pub unsafe extern "C" fn hivra_starter_get_id(slot: u8, out_id: *mut u8) -> i32 {
    if out_id.is_null() || slot >= 5 {
        return -1;
    }
    
    // Return dummy starter ID based on slot
    let base = slot as u8;
    let id = [
        base, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, base + 1,
    ];
    std::ptr::copy_nonoverlapping(id.as_ptr(), out_id, 32);
    0
}

#[no_mangle]
pub unsafe extern "C" fn hivra_starter_get_type(slot: u8) -> i32 {
    if slot >= 5 {
        return -1;
    }
    // Return different types for different slots
    slot as i32
}

#[no_mangle]
pub unsafe extern "C" fn hivra_starter_exists(slot: u8) -> i8 {
    if slot >= 5 {
        return 0;
    }
    1 // All slots exist for demo
}
