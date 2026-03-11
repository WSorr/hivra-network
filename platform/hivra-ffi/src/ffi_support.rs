use super::*;

/// Structure for returning serialized bytes
#[repr(C)]
pub struct FfiBytes {
    pub data: *mut u8,
    pub len: usize,
}

/// Free string allocated by FFI
#[no_mangle]
pub unsafe extern "C" fn hivra_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

/// Free memory allocated by capsule_state_encode
#[no_mangle]
pub unsafe extern "C" fn free_bytes(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        let _ = Vec::from_raw_parts(ptr, len, len);
    }
}
