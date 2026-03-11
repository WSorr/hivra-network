# Hivra v3.2*: CONCEPTUAL MODEL

Hive Integrated Value & Relationship Architecture

Version: 3.2.*
Status: Final
Date: 2026-02-20

---

## Documentation and Comment Language Requirements

### 1. Documentation Language

All user-facing documentation, README files, API docs, guides, and examples published in open repositories or shipped with the product MUST be written in ENGLISH.

This includes (but is not limited to):

- README.md in the root and in every crate
- API docs (/// comments generating rustdoc)
- Code examples in examples/
- Commit messages
- Pull Request descriptions
- Wiki pages (if used)

### 2. Code Comment Language

All comments in production code MUST be in ENGLISH.

```rust
// Correct:
/// Returns the current timestamp from the time source.
pub fn now(&self) -> Timestamp {
    self.time.now()
}

// Incorrect:
/// Возвращает текущую метку времени из источника времени.
pub fn now(&self) -> Timestamp {
    self.time.now()
}
```

### 3. Exceptions

Only the following are exceptions:

- Internal team documents (like this one)
- Temporary development comments (TODO, FIXME) — must be translated or removed before release
- Specific terms without adequate translation

### 4. Rationale

1. Global audience: code and documentation are read by developers worldwide
2. Open Source: English is the standard for open source
3. Tooling: Rust ecosystem (rustdoc, crates.io) is oriented around English
4. Onboarding: new non-Russian-speaking developers must be able to contribute

### 5. Enforcement

Commits containing non-English documentation or comments (in production-bound files) must not pass review and must be corrected.

---

## 0. Introduction

Hivra is infrastructure for relationships, not a social network. There are no likes, followers, or algorithmic feeds. There is only you, your 5 unique starters, and people you trust.

Metaphor: Imagine you have 5 unique slippers. Each has its own distinct pattern (Juice, Spark, Seed, Pulse, Kick). You cannot give your slipper away — it always stays with you. But you can invite someone so they create their own slipper with the same pattern. When you both have slippers with the same pattern, a relationship forms.

If you invite someone who does not have that slipper and they refuse to create it — your slipper is destroyed. Forever.

---

## 1. Fundamental Principles (DO NOT VIOLATE)

1. No global discovery — only manual add via pubkey
2. Network is built on invitations, not search
3. Android can be Relay, iOS only Leaf (optional)
4. Starters are unique identifiers, not economic tokens
5. Starter names are just names (Juice/Spark/Seed/Pulse/Kick), not functions
6. Transport is an abstraction layer (currently Nostr, others can be added)
7. Reputation is local only (for relay scoring)
8. No VPS (except seed, but we do not host them)
9. Trust is more important than convenience
10. Starter always stays with the creator

---

## 2. Entities

### 2.1 Capsule

Capsule is you. An application instance, your identity.

What a capsule has:

- Public key — the only identifier
- 5 slots — exactly five, no more, no less
- Role — Leaf (regular) or Relay (forwarder, Android only)
- Trusted peers — list of capsules allowed to store your messages (Relay only)
- Ledger — local signed log of all events
- Two networks — Neste (main) and Hood (test) — fully isolated states

Capsule states on first launch:

- No capsules → user creates the first (Proto or Genesis)
- Capsules exist → show capsule selector

Managing multiple capsules:

- Capsules are independent (different seed, different ledger)
- Switch at any time
- Create new capsule from selector

### 2.2 Starter

Starter is a unique, non-fungible asset. Your DNA in the network.

Properties:

- ID — 32 bytes, globally unique
- Type — Juice, Spark, Seed, Pulse, Kick (just names)
- Owner — creator (always one, never changes)
- Origin — who invited you
- Network — Neste or Hood
- Creation time

Rules:

- Starter cannot be transferred
- Type never changes
- Starter can only be burned (when recipient rejects with empty slot)

### 2.3 Slot

Slot is a place for your starter.

Characteristics:

- Exactly 5 slots per capsule (indices 0-4)
- Slot holds ONLY your starter
- Type is not bound to position (Juice can be in any slot)
- Slot can be locked (during invitation)

### 2.4 Ledger (Local Register)

Ledger is the heart of the capsule. Everything is recorded here.

What it stores:

- All signed events (who, when, with whom)
- Current relationship projection (built from events)

Event types:

- InvitationSent — invitation sent
- InvitationAccepted — invitation accepted
- InvitationRejected — invitation rejected
- RelationshipEstablished — relationship created
- RelationshipBroken — relationship broken

### 2.5 Relationship

Relationship is the fact of mutual recognition between two capsules.

Properties:

- Peer (pubkey)
- Starter type (which type the relationship is based on)
- Peer starter ID
- Own starter ID
- Timestamp

Important: One starter can participate in multiple relationships. 5 starters != 5 relationships.

### 2.6 Role

Leaf — regular capsule:

- Can send invitations (if free starters exist)
- Can accept invitations
- Can reject invitations
- Can break relationships

Relay — Android only, manual enable:

- Same as Leaf
- Can store messages for trusted peers
- Can relay (battery-aware)

### 2.7 Trusted Peers

List of capsules allowed to store your messages.

How to add: manual only (QR, NFC, manual pubkey)

What it enables: Relay stores messages for the peer

What it does NOT enable: auto-accept invitations, starter access

### 2.8 Networks

Two fully isolated universes:

Network | Purpose
--- | ---
Neste | Main, production
Hood | Test, sandbox

Rules:

- Full isolation (events from Neste do not affect Hood)
- Each capsule has two independent slot sets
- Same type in different networks = different starters

---

## 3. Mechanics

### 3.1 Invitations (Full Flow)

Phase 1: Initiation (A → B)

1. A selects their starter of type X
2. Starter is locked (cannot be used in other invitations)
3. A creates InvitationSent in their ledger
4. Invitation is delivered to B via transport layer

Phase 2: Receive and Decide (B)

B receives invitation and checks:

1. Do they already have a starter of type X?
2. Is there any empty slot?

Case A: No own X + empty slot + ACCEPT

- B generates a NEW starter of type X
- B creates InvitationAccepted
- B creates RelationshipEstablished with A
- A receives confirmation, unlocks their starter
- A creates RelationshipEstablished with B
- Result: relationship established using the newly created X

Case B: Empty slot + REJECT (BURN)

- UI warns: "Starter A will be destroyed"
- B confirms rejection
- B creates InvitationRejected with reason EmptySlot
- A receives, DELETES their starter (burned)
- Result: A lost starter, no relationship

Case C: Own X exists + empty slot + ACCEPT

- B keeps using their existing X for the relationship
- B generates one NEW starter of a type that is still missing in their set
- B creates InvitationAccepted
- B creates RelationshipEstablished
- A receives, unlocks their starter
- A creates RelationshipEstablished
- Result: relationship established on existing X, and B fills one missing type

Case D: Own X exists + no empty slot + ACCEPT

- B creates InvitationAccepted
- B creates RelationshipEstablished
- A receives, unlocks their starter
- A creates RelationshipEstablished
- Result: relationship established, no new starter created

Case E: Slot occupied + REJECT

- B creates InvitationRejected with reason Other
- A receives, unlocks their starter
- Result: no relationship

Case F: Timeout (B no response)

- A can cancel after 24 hours
- Starter A is unlocked

### 3.2 Burn Rule (CRITICAL)

A starter is burned ONLY when ALL conditions are met:

1. Recipient has no starter of that type and has an empty slot
2. Recipient explicitly rejects the invitation
3. Recipient confirmed the burn warning

### 3.3 Relationships

Establishing:

- Happens automatically on successful acceptance
- Recorded in both ledgers

Breaking:

- Either side can break at any time
- RelationshipBroken recorded in ledger
- Starters are NOT burned on break

### 3.4 Relay

Relay conditions:

1. Relay role enabled in settings
2. Recipient is in trusted_peers
3. Battery > 20%
4. Free space available

Process:

1. A sends message to B
2. Relay V (trusted by B) stores message
3. B comes online
4. Relay V forwards message
5. Relay V deletes stored message

Retention time: 24 hours

Relay off: all stored foreign messages are deleted immediately

### 3.5 Local Reputation

Only for rating relay reliability. Local only.

Signals:

- How many times relay delivered
- How many times relay failed

Used for: UI hints only, no protocol influence

---

## 4. Exceptional Cases

Scenario | Outcome
--- | ---
Invitation received, no own type, empty slot, accepted | New starter for B, relationship, starter A unlocked
Invitation received, own type exists, empty slot, accepted | Relationship established on existing type, one missing starter created, starter A unlocked
Invitation received, own type exists, no empty slot, accepted | Relationship established on existing type, starter A unlocked
Invitation received, empty slot, rejected | STARTER A BURNED
Invitation received, slot occupied, rejected | Starter A unlocked, no relationship
Recipient offline | Relay (if trusted) stores for 24h
No response for 24h | Message deleted, starter A unlocked
Relay turned off | All stored messages deleted
Relationship broken | Relationship removed, starters remain
Invite with locked starter | Error: starter busy

---

## 5. Transport Layer (Extensibility)

Hivra v3.2 ships with Nostr as the main transport, but the architecture allows others:

Supported transports (plugins):

- Nostr (built-in)
- Matrix (plugin)
- Bluetooth LE (plugin, mesh)
- Local network (plugin, offline enclaves)

How it works:

- Capsule can use one or multiple transports
- Message is broadcast to all recipient transports
- Recipient accepts the first delivered

Guarantees:

- Ledger does not know which transport delivered the event
- Determinism is preserved

---

## 6. v3.2 Limitations (Not Implemented)

- Friend-based recovery (planned for v4.x)
- Kick mechanic (forced break)
- Multisignatures
- Temporary starters
- Group capsules
- Economy and tokens

---

## 7. Glossary

Term | Definition
--- | ---
Capsule | App instance, your identity
Starter | Unique non-fungible asset
Slot | Place for your starter (exactly 5)
Ledger | Local signed log of events
Relationship | Fact of mutual recognition
Relay | Android capsule storing others' messages
Trusted peer | Capsule allowed to store messages
Neste | Main network
Hood | Test network
Burning | Destroying a starter after empty-slot rejection

---

End of document 1
