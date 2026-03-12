#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATUS=0

pass() {
  printf 'PASS topology: %s\n' "$1"
}

warn() {
  printf 'WARN topology: %s\n' "$1"
}

fail() {
  printf 'FAIL topology: %s\n' "$1"
  STATUS=1
}

expect_dir() {
  local path="$1"
  if [ -d "$ROOT/$path" ]; then
    pass "found $path"
  else
    warn "missing $path (target topology not created yet)"
  fi
}

expect_file() {
  local path="$1"
  if [ -f "$ROOT/$path" ]; then
    pass "found $path"
  else
    fail "missing required file $path"
  fi
}

expect_file "Cargo.toml"
expect_dir "core"
expect_dir "adapters"
expect_dir "platform"
expect_dir "flutter"
expect_dir "tools/review"

if [ -d "$ROOT/adapters/hivra-transport" ]; then
  pass "transport adapter isolated under adapters/: adapters/hivra-transport"
else
  fail "missing transport adapter at adapters/hivra-transport"
fi

if [ -d "$ROOT/adapters/hivra-nostr-crypto" ]; then
  pass "crypto adapter isolated under adapters/: adapters/hivra-nostr-crypto"
else
  fail "missing crypto adapter at adapters/hivra-nostr-crypto"
fi

if [ -d "$ROOT/core/hivra-transport" ]; then
  fail "legacy transport crate path still exists under core/: core/hivra-transport"
fi

if [ -d "$ROOT/core/hivra-nostr-crypto" ]; then
  fail "legacy crypto adapter path still exists under core/: core/hivra-nostr-crypto"
fi

if [ -d "$ROOT/platform/hivra-ffi" ]; then
  pass "ffi crate isolated under platform/: platform/hivra-ffi"
fi

if [ -d "$ROOT/platform/hivra-keystore" ]; then
  pass "keystore adapter isolated under platform/: platform/hivra-keystore"
fi

exit "$STATUS"
