# Hivra Protocol v3.2 — Full Specification

Version: 3.2
Date: 2026-02-20

Hive Integrated Value & Relationship Architecture

---

## 0. Preamble

This document is the single source of truth for the architecture and implementation of the HIVRA v3.2 protocol. It defines a strict layered architecture, domain invariants, data formats, and participant roles.

The key change in v3.2 is a hard rule: Core knows nothing about transport, cryptography, time, or RNG. All external dependencies are injected through the Engine.

---

## 1. Philosophy and Fundamental Principles

### 1.1 Core Values

1. No global discovery — only manual add by public key.
2. The network is built on invitations, not search.
3. Starters are unique identifiers, not economic tokens. They cannot be transferred.
4. Transport is an abstraction layer. Nostr now, but Matrix, BLE, and others can be added.
5. Reputation is local only (for relay scoring).
6. Trust is more important than convenience — the user controls all critical actions.

### 1.2 Determinism Principles

The system guarantees:

- Same input → same output (binary).
- Full state recovery from the ledger.
- No hidden sources of non-determinism.
- Full layer isolation.

---

## 2. Layered Architecture (Dependency Rule)

### 2.1 Dependency Rule

Dependencies are allowed only downward. Inner layers do not know about outer layers.

```
UI (Flutter)
    ↓
Transport Adapters (Nostr, Matrix, BLE...)
    ↓
Engine (orchestrator, time, RNG, cryptography)
    ↓
Core (domain logic, agnostic)
```

Forbidden:

- Core does not know about Engine.
- Core does not know about Transport.
- Engine does not know about UI.
- Transport does not know about Core.
- Violating this rule is an architectural error.

### 2.2 Separation of Responsibilities

Layer | Responsible For | Knows Nothing About
--- | --- | ---
UI | Rendering, user input | Domain logic, transport
Transport | Byte transfer, network adaptation | Business meaning, cryptography
Engine | Orchestration, dependency injection, signature validation | Detailed event structure (only bytes)
Core | Domain invariants, events, projections | Time, RNG, I/O, JSON, cryptography

---

## 3. Core (Domain Layer)

### 3.1 General Rules

Core is the innermost layer. It:

- Contains entities, invariants, events, and state transition rules.
- Performs only deterministic computation.
- Does not use system time, RNG, or I/O.
- Does not know JSON or any serialization formats except binary.
- Does not know cryptography — keys and signatures are just bytes.

Core operates only on:

- Bytes.
- Pure data structures.
- Input parameters passed from Engine.

### 3.2 Core Primitives

```rust
/// Public key — 32 bytes.
/// Core DOES NOT KNOW which curve is used (secp256k1, ed25519...).
pub struct PubKey([u8; 32]);

/// Private key — 32 bytes. NEVER passed into Core.
pub struct PrivKey([u8; 32]);

/// Signature — 64 bytes. Core does not verify signatures.
pub struct Signature([u8; 64]);

/// Starter ID — 32 bytes.
pub struct StarterId([u8; 32]);
```

### 3.3 Core Entities

#### 3.3.1 Capsule

Capsule is an application instance, the user identity.

```rust
struct Capsule {
    pubkey: PubKey,           // 32 bytes, identifier
    network: Network,          // Neste | Hood
    ledger: Ledger,            // append-only event log
    // Slots are a projection from the ledger, not stored directly
}
```

#### 3.3.2 Starter

Starter is a unique non-fungible identifier.

```rust
struct Starter {
    id: StarterId,             // 32 bytes
    owner: PubKey,             // creator (immutable)
    kind: StarterKind,          // Juice, Spark, Seed, Pulse, Kick
    network: Network,
    origin_invitation: Option<[u8; 32]>, // invitation origin
    created_at: Timestamp,      // creation time (from Engine)
    state: StarterState,        // Active | Burned
}
```

Rules:

- Starter cannot be transferred to another owner.
- Type never changes.
- Created only via StarterCreated.
- Burned only via StarterBurned.

#### 3.3.3 Slot

Slot is a position (0..4) for your starter.

- Slot holds only your starter.
- Type is not bound to position (Juice can be in any slot).
- Slot can be locked (during invitation).

Lock is derived from the ledger:

```rust
fn is_locked(starter_id: StarterId, ledger: &Ledger) -> bool {
    // Locked if there is InvitationSent and no finalizing event
}
```

#### 3.3.4 Ledger

Ledger is an append-only log of signed events.

- Single source of truth.
- Full state is recovered by replaying events.
- Events are immutable; deletion or overwrite is forbidden.

#### 3.3.5 Relationship

Relationship is the fact of mutual recognition between two capsules.

```rust
struct Relationship {
    peer: PubKey,               // relationship peer
    own_starter_id: StarterId,   // own starter
    peer_starter_id: StarterId,  // peer starter
    kind: StarterKind,           // type (Juice/Spark/...)
    established_at: Timestamp,
}
```

Relationship is active if:

- There is RelationshipEstablished.
- There is no local RelationshipBroken.

### 3.6 Multiple Capsule Management

Users can have multiple independent capsules.

Storage:

- Each capsule has its own seed in Keychain.
- Capsule metadata stored under "capsule_metadata".

Selector screen:

- Shown on launch if at least one capsule exists.
- Displays public key, network, starter count.
- Allows creating a new capsule.

Switching:

- Selecting a capsule loads its seed and ledger.
- Previous capsule is unloaded from memory.

---

## 4. Engine (Orchestrator)

### 4.1 Role of Engine

Engine is the single orchestration point. It:

- Injects dependencies (time, RNG, cryptography).
- Manages TimeSource and RandomSource.
- Calls CryptoProvider.
- Manages transport.
- Contains no domain invariants.

### 4.2 External Dependency Interfaces

```rust
pub trait TimeSource {
    fn now(&self) -> Timestamp;
}

pub trait RandomSource {
    fn fill_bytes(&self, buf: &mut [u8]);
}

pub trait CryptoProvider {
    /// Verify signature
    fn verify(&self, msg: &[u8], pubkey: &[u8; 32], sig: &[u8; 64]) -> Result<(), Error>;

    /// Sign message
    fn sign(&self, msg: &[u8], privkey: &[u8; 32]) -> Result<[u8; 64], Error>;

    /// (Optional) ECDH for encryption
    fn ecdh(&self, privkey: &[u8; 32], pubkey: &[u8; 32]) -> Result<[u8; 32], Error>;
}
```

### 4.3 Incoming Event Validation

```rust
fn validate_incoming_event(
    &self,
    raw_bytes: &[u8],
    pubkey: &PubKey,
    signature: &Signature,
) -> Result<ValidatedEvent, Error> {
    // 1. Crypto verification (CryptoProvider)
    self.crypto.verify(raw_bytes, pubkey.as_bytes(), signature.as_bytes())?;

    // 2. Deserialize into domain event (binary format)
    let event: DomainEvent = bincode::deserialize(raw_bytes)?;

    // 3. Structural validation (domain rules)
    event.validate_structure()?;

    Ok(ValidatedEvent::from(event))
}
```

---

## 5. Transport Layer

### 5.1 Principles

- Transport only transfers bytes.
- Does not interpret payload.
- Does not perform business logic.
- Does not generate time.
- Does not create keys.

### 5.2 Supported Transports

- Nostr (built-in, secp256k1)
- Matrix (plugin, ed25519)
- BLE (plugin)
- Local network (plugin)

Each transport provides:

1. Transport implementation (send/receive bytes).
2. CryptoProvider implementation (for its curve).

### 5.3 Unified Message Format

```rust
struct Message {
    from: PubKey,
    to: PubKey,
    kind: u32,              // event type (Invitation, Relationship...)
    payload: Vec<u8>,       // serialized event
    timestamp: u64,
    invitation_id: Option<[u8; 32]>,
    transport_hints: Vec<Hint>,
}
```

### 5.4 Nostr Adapter (Example)

```
Core bytes → base64 → Nostr content
```

```rust
// NostrTransport uses NostrCryptoProvider (secp256k1)
pub struct NostrCryptoProvider {
    secp: Secp256k1,
}

impl CryptoProvider for NostrCryptoProvider {
    fn verify(&self, msg: &[u8], pubkey: &[u8; 32], sig: &[u8; 64]) -> Result<()> {
        // Interpret bytes as secp256k1 x-only pubkey
        let pubkey = XOnlyPublicKey::from_slice(pubkey)?;
        let sig = schnorr::Signature::from_slice(sig)?;
        self.secp.verify_schnorr(&sig, msg, &pubkey)?;
        Ok(())
    }
}
```

---

## 6. Cryptographic Layer (CryptoProvider)

### 6.1 Architectural Position

CryptoProvider is implemented per transport. It lives in Engine, NOT in Core.

### 6.2 Why Core Knows Nothing About Crypto

- Core operates on raw bytes ([u8; 32], [u8; 64]).
- Interpreting those bytes as public keys or signatures happens only in CryptoProvider.
- This enables any curve (secp256k1, ed25519, ...) without changing Core.

### 6.3 Example Implementations

- NostrCryptoProvider: secp256k1 (Schnorr signatures)
- MatrixCryptoProvider: ed25519
- MockCryptoProvider: tests (always succeeds)

---

## 7. Events (Domain Events)

All state changes happen through signed events.

### 7.1 Base Fields

```rust
struct Event {
    version: u8,        // protocol version (3)
    kind: EventKind,     // event type
    payload: Vec<u8>,    // type-specific fields (binary)
    timestamp: u64,      // from Engine
    signature: Signature,// capsule owner signature
}
```

### 7.2 Event Types

Event | Fields
--- | ---
InvitationSent | invitation_id, starter_id, to_pubkey
InvitationAccepted | invitation_id, from_pubkey, created_starter_id (recipient starter used for the relationship; if accept created a new invited starter, this is that starter ID)
InvitationRejected | invitation_id, reason (EmptySlot | Other)
InvitationExpired | invitation_id
StarterCreated | starter_id, nonce, kind, network
StarterBurned | starter_id, reason
RelationshipEstablished | peer_pubkey, own_starter_id, peer_starter_id, kind
RelationshipBroken | peer_pubkey, own_starter_id

---

## 8. Mechanics

### 8.1 Invitations (Full Flow)

Phase 1: Initiation (A → B)

1. A selects starter of type X (slot must be free).
2. Starter is locked (cannot be used in other invitations).
3. A creates InvitationSent in its ledger.
4. Engine signs and sends via transport.

Phase 2: Receive (B)

B receives invitation. Check:

1. Is there already a starter of type X?
2. Is there any empty slot?

Situation | B Action | Result
--- | --- | ---
No own X + empty slot + Accept | Create new starter of type X + InvitationAccepted + RelationshipEstablished | Relationship uses the newly created X
Own X exists + empty slot + Accept | Create one missing starter type + InvitationAccepted + RelationshipEstablished | Relationship uses existing X; created starter fills a missing type
Own X exists + no empty slot + Accept | InvitationAccepted + RelationshipEstablished | Relationship uses existing X; no new starter is created
No own X + no empty slot + Accept | Accept is impossible | No acceptance without capacity for invited type
Empty slot + Reject | InvitationRejected(EmptySlot) | A's starter is burned
Slot occupied + Reject | InvitationRejected(Other) | A's starter is unlocked
Timeout (24h) | - | A's starter unlocked

### 8.2 Burn Rule (Critical)

A starter is burned ONLY at the sender and only when ALL conditions are met:

1. Recipient has no starter of the invited type and has an empty slot.
2. Recipient explicitly rejects the invitation.
3. Recipient confirmed the burn warning.
4. Sender's starter is burned.

### 8.3 Relationships

- Established automatically on successful acceptance.
- Recorded in both ledgers.
- Either side can break at any time (RelationshipBroken).
- Starters are not burned on break.

---

## 9. Invariants (DO NOT VIOLATE)

1. Each capsule has exactly 5 slots.
2. Starter cannot change owner.
3. Starter cannot change type.
4. Starter can only be Active or Burned.
5. Ledger is the single source of truth.
6. Capsule state fully recovers from ledger.
7. All state changes occur via events.
8. Core does not call time, RNG, or crypto.
9. Private key is never passed into Core.

---

## 10. Data Formats and Serialization

### 10.1 Rules

- All structures are encoded only in binary.
- Allowed formats: bincode (recommended), postcard.
- JSON is forbidden inside Core.
- Encoding: little-endian, fixed-length integers.

### 10.2 Identifiers

All IDs are computed deterministically:

```rust
// Starter ID
SHA256(owner_pubkey || network || kind || creation_nonce)

// Event ID
SHA256(version || kind || payload_bytes)
```

- Event ID is never computed from JSON, base64, or transport representation.

---

## 11. Roles

### 11.1 Leaf (Regular Capsule)

- Can send/accept invitations.
- Can reject invitations.
- Can break relationships.

### 11.2 Relay (Forwarder, Android Only)

- Same as Leaf.
- Can store messages for trusted peers.
- Requires battery > 20% and free space.
- Retention max 24 hours.
- Turning off Relay deletes all stored messages.

### 11.3 Trusted Peers

List of capsules allowed to store messages.

- Add: manual only (QR, NFC, manual pubkey).
- Relay stores messages only for trusted peers.

---

## 12. Networks

Two fully isolated universes:

Network | Purpose
--- | ---
Neste | Main, production
Hood | Test, sandbox

Rules:

- Full isolation (events from Neste do not affect Hood).
- Each capsule has two independent slot sets.
- Same type in different networks = different starters.

---

## 13. v3.2 Limitations (Not Implemented)

- Friend-based recovery (planned for v4.x)
- Kick mechanic (forced break)
- Multisignatures
- Temporary starters
- Group capsules
- Economy and tokens

---

## 14. Glossary

Term | Definition
--- | ---
Capsule | App instance, user identity
Starter | Unique non-fungible identifier
Slot | Place for your starter (exactly 5)
Ledger | Local signed log of events
Relationship | Fact of mutual recognition
Relay | Android capsule storing others' messages
Trusted peer | Capsule allowed to store messages
Neste | Main network
Hood | Test network
Burning | Destroying a starter after empty-slot rejection
CryptoProvider | Cryptography interface in Engine (transport-specific)

---

## 15. Status and Readiness

HIVRA Protocol v3.2 in this revision is:

- Architecturally clean (strict downward dependencies)
- Logically consistent
- Deterministic (Core has no external dependencies)
- Transport-agnostic (Core is crypto-agnostic)
- Ready for formal audit
- Ready for implementation: Rust Core + Flutter UI

---

## 16. UI Screen Contract (Screen Standard and Content)

### 16.1 Scope

Contract is mandatory for:

- Capsule Selector screen
- Main screen and all its tabs
- Starters, Invitations, Relationships, Settings screens
- All future top-level capsule state screens

### 16.2 Source of Truth

1. All capsule metrics in UI MUST be computed from ledger/state projection.
2. Hardcoded counters in headers are FORBIDDEN.
3. Fallback mode is allowed only when ledger export is unavailable and must be explicit and deterministic.

### 16.3 Global Top-Level Screen Structure

Each top-level screen MUST include:

1. AppBar with screen title.
2. Capsule header:
   - network badge (`NESTE` or `HOOD`)
   - capsule public key (visually shortened)
   - counters: `Starters`, `Relationships`, `Pending`
   - ledger metadata: `version`, short `hash`
3. Content area.
4. Bottom navigation with fixed order:
   - Starters
   - Invitations
   - Relationships
   - Settings

### 16.4 Terminology (Required)

UI must use only domain terms:

- Capsule
- Starter
- Invitation
- Relationship
- Ledger
- Network (`NESTE` / `HOOD`)

### 16.5 Visual Consistency

1. Network color fixed:
   - `NESTE` -> green palette
   - `HOOD` -> orange palette
2. Counter colors fixed:
   - Starters -> blue
   - Relationships -> green
   - Pending -> orange
3. Public keys and hashes displayed in monospace.
4. Empty-state pattern: icon + title + explanation + primary action.

### 16.6 Minimum Data Per Screen

Capsule Selector row MUST show:

- network
- short public key
- starters / relationships / pending
- ledger version / hash
- last active marker

Main header MUST show:

- network
- short public key
- starters / relationships / pending
- ledger version / hash

### 16.7 Change Rule

Any PR that changes screen structure, labels, metrics, or visual tokens must:

1. Keep this contract unchanged, or
2. Update this section in the same PR with justification.

UI changes that violate the contract do not pass review.
