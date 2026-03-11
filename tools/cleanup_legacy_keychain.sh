#!/usr/bin/env bash
set -euo pipefail

SERVICE="com.hivra.keystore"
LEGACY_ACCOUNT="capsule_seed"

if ! command -v security >/dev/null 2>&1; then
  echo "security CLI not found (macOS keychain tool is required)"
  exit 1
fi

echo "Removing legacy keychain entry: service=${SERVICE}, account=${LEGACY_ACCOUNT}"
if security delete-generic-password -s "${SERVICE}" -a "${LEGACY_ACCOUNT}" >/dev/null 2>&1; then
  echo "Legacy entry removed."
else
  echo "Legacy entry not found (nothing to remove)."
fi
