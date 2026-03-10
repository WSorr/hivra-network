#!/bin/bash
# Copy FFI library to Frameworks folder

# Resolve library path relative to this project instead of using a hardcoded machine-specific path.
PROJECT_ROOT="${SRCROOT}/../.."
LIB_SRC_DEBUG="${PROJECT_ROOT}/target/debug/libhivra_ffi.dylib"
LIB_SRC_RELEASE="${PROJECT_ROOT}/target/release/libhivra_ffi.dylib"
APP_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Contents/Frameworks/"

if [ -f "${LIB_SRC_DEBUG}" ]; then
    LIB_SRC="${LIB_SRC_DEBUG}"
elif [ -f "${LIB_SRC_RELEASE}" ]; then
    LIB_SRC="${LIB_SRC_RELEASE}"
else
    echo "ERROR: Library not found. Checked:"
    echo "  - ${LIB_SRC_DEBUG}"
    echo "  - ${LIB_SRC_RELEASE}"
    exit 1
fi

echo "=== Copying FFI Library ==="
echo "LIB_SRC: ${LIB_SRC}"
echo "APP_PATH: ${APP_PATH}"

mkdir -p "${APP_PATH}"
cp -v "${LIB_SRC}" "${APP_PATH}"

if [ -f "${APP_PATH}/libhivra_ffi.dylib" ]; then
    echo "SUCCESS: Library copied"
    ls -la "${APP_PATH}/libhivra_ffi.dylib"
    
    # Fix library install name
    install_name_tool -id "@rpath/libhivra_ffi.dylib" "${APP_PATH}/libhivra_ffi.dylib"
else
    echo "ERROR: Library not found after copy"
    exit 1
fi

echo "=== Copy complete ==="
