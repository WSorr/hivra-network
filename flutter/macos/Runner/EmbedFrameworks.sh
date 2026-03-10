#!/bin/bash
# Copy Hivra framework into the app bundle

if [ -d "${TARGET_BUILD_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks" ]; then
    mkdir -p "${TARGET_BUILD_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"
fi

# Copy the dylib
cp "${SRCROOT}/../Frameworks/libhivra_ffi.dylib" \
   "${TARGET_BUILD_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks/"

# Make sure it's executable
chmod 755 "${TARGET_BUILD_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks/libhivra_ffi.dylib"
