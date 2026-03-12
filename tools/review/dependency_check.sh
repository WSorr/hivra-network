#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS=0

pass() {
  printf 'PASS dependency: %s\n' "$1"
}

fail() {
  printf 'FAIL dependency: %s\n' "$1"
  STATUS=1
}

warn() {
  printf 'WARN dependency: %s\n' "$1"
}

require_present() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if rg -q "$pattern" "$file"; then
    pass "$message"
  else
    fail "$message"
  fi
}

require_absent() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if rg -q "$pattern" "$file"; then
    fail "$message"
  else
    pass "$message"
  fi
}

CORE_TOML="$ROOT/core/hivra-core/Cargo.toml"
ENGINE_TOML="$ROOT/core/hivra-engine/Cargo.toml"
TRANSPORT_TOML="$ROOT/adapters/hivra-transport/Cargo.toml"
CRYPTO_TOML="$ROOT/adapters/hivra-nostr-crypto/Cargo.toml"
FFI_TOML="$ROOT/platform/hivra-ffi/Cargo.toml"

require_absent "$CORE_TOML" 'hivra-(engine|transport|nostr-crypto|ffi|keystore)' \
  "hivra-core must not depend on engine/transport/crypto/ffi/keystore"

require_present "$ENGINE_TOML" 'hivra-core' \
  "hivra-engine depends on hivra-core"
require_absent "$ENGINE_TOML" 'hivra-(transport|nostr-crypto|ffi|keystore)' \
  "hivra-engine must not depend on transport/crypto/ffi/keystore"

require_present "$TRANSPORT_TOML" 'hivra-core' \
  "hivra-transport depends on hivra-core"
require_absent "$TRANSPORT_TOML" 'hivra-ffi' \
  "hivra-transport must not depend on hivra-ffi"

require_present "$CRYPTO_TOML" 'hivra-engine' \
  "hivra-nostr-crypto depends on hivra-engine"
require_absent "$CRYPTO_TOML" 'hivra-ffi' \
  "hivra-nostr-crypto must not depend on hivra-ffi"

require_present "$FFI_TOML" 'hivra-core' \
  "hivra-ffi depends on hivra-core"
require_present "$FFI_TOML" 'hivra-engine' \
  "hivra-ffi depends on hivra-engine"
require_present "$FFI_TOML" 'hivra-transport' \
  "hivra-ffi depends on hivra-transport"
require_present "$FFI_TOML" 'hivra-nostr-crypto' \
  "hivra-ffi depends on hivra-nostr-crypto"
require_present "$FFI_TOML" 'hivra-keystore' \
  "hivra-ffi depends on hivra-keystore"

if rg -q 'path = "../../core/(hivra-transport|hivra-nostr-crypto)"' "$FFI_TOML"; then
  fail "hivra-ffi still points adapter dependencies into core/"
else
  pass "hivra-ffi adapter paths no longer point into core/"
fi

exit "$STATUS"
