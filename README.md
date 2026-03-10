# Hivra Protocol

Hivra is an infrastructure for relationships, not a social network. No likes, no followers, no algorithmic feeds. Only you, your 5 unique starters, and people you trust.

## Architecture

This repository implements Hivra v3.2 specification:

- **Core** — Pure domain logic (deterministic, no I/O, no crypto knowledge)
- **Engine** — Orchestration layer (time, RNG, crypto provider)
- **Transport** — Abstract transport layer (Nostr, Matrix, BLE)
- **Platform** — OS-specific implementations (SecureKeyStore)
- **Flutter UI** — Cross-platform interface

## Specification Documents

- [Hivra Protocol v3.2 Full Specification](docs/hivra-v3.2-full-specification.md)
- [Hivra v3.2 Conceptual Model](docs/hivra-v3.2-conceptual-model.md)
- [Hivra v3.2 UI Screen Standard](docs/hivra-v3.2-ui-screen-standard.md)
- [Documentation and Code Comment Language Policy](docs/documentation-language-policy.md)

## Identity and Key Derivation

- One capsule is backed by one recovery seed phrase (BIP39).
- Transport keys are derived deterministically from that seed using domain-separated labels.
- Different transports may use different curves while sharing the same recovery phrase:
  - Nostr: secp256k1
  - Other adapters (for example Matrix): ed25519
- Recovery requires only the seed phrase and derivation version compatibility.

## Capsule Lifecycle in UI

### First Launch States

- **No capsules**: the user creates the first capsule (`Proto` or `Genesis`).
- **Existing capsules**: the app opens the capsule selection screen.

### Multi-Capsule Management

Users can own multiple independent capsules.

- Capsules are independent (`seed` and `ledger` are isolated per capsule).
- Capsule switching is available at any time.
- New capsule creation is available from the capsule selection UI.

### Capsule Storage

- Each capsule has its own seed stored in Keychain.
- Capsule metadata is stored under a separate key: `capsule_metadata`.

### Capsule Selection Screen

Shown on app launch when at least one capsule exists.

- Displays capsule public key.
- Displays active network.
- Displays starter count.
- Allows creating a new capsule.

### Switching Capsules

- On selection, the app loads the selected capsule seed and ledger.
- The previously active capsule is unloaded from memory.

## Building

### Prerequisites

- Rust 1.75+
- Flutter 3.22+
- Android SDK (API 36) for Android builds
- Xcode 15+ for macOS builds

### Build

```bash
# Build all Rust crates
cargo build --release

# Build Flutter for current dev target (macOS)
cd flutter
flutter build macos
```

For current local development, use macOS target only (`flutter run -d macos`).

## License

MIT
