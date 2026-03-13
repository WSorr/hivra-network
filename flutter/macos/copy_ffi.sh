#!/bin/bash
set -euo pipefail

PROJECT_ROOT="${SRCROOT}/../.."
APP_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Contents/Frameworks"
UNIVERSAL_LIB="${APP_PATH}/libhivra_ffi.dylib"

if [ "${CONFIGURATION:-Debug}" = "Release" ]; then
    CARGO_PROFILE_FLAG="--release"
    LIB_SUBDIR="release"
else
    CARGO_PROFILE_FLAG=""
    LIB_SUBDIR="debug"
fi

ARM_TARGET="aarch64-apple-darwin"
INTEL_TARGET="x86_64-apple-darwin"
ARM_LIB="${PROJECT_ROOT}/target/${ARM_TARGET}/${LIB_SUBDIR}/libhivra_ffi.dylib"
INTEL_LIB="${PROJECT_ROOT}/target/${INTEL_TARGET}/${LIB_SUBDIR}/libhivra_ffi.dylib"

echo "=== Building universal Hivra FFI ==="
echo "PROJECT_ROOT: ${PROJECT_ROOT}"
echo "CONFIGURATION: ${CONFIGURATION:-Debug}"

cd "${PROJECT_ROOT}"
cargo build -p hivra-ffi --target "${ARM_TARGET}" ${CARGO_PROFILE_FLAG}
cargo build -p hivra-ffi --target "${INTEL_TARGET}" ${CARGO_PROFILE_FLAG}

mkdir -p "${APP_PATH}"
lipo -create -output "${UNIVERSAL_LIB}" "${ARM_LIB}" "${INTEL_LIB}"
install_name_tool -id "@rpath/libhivra_ffi.dylib" "${UNIVERSAL_LIB}"
chmod 755 "${UNIVERSAL_LIB}"

echo "SUCCESS: Universal library created"
file "${UNIVERSAL_LIB}"
echo "=== Copy complete ==="
