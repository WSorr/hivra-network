# Hivra Docs Map

This folder contains the canonical project documentation for Hivra v3.2.12.

## Documents

### 1) `specification.md` (normative)
Use this as the source of truth for implementation and review.

Contains:
- protocol architecture and dependency rules
- Core/Engine/Transport boundaries
- domain events, invariants, serialization rules
- role and network rules
- UI Screen Contract requirements

If there is any conflict, `specification.md` wins.

### 2) `hivra-v3.2-conceptual-model.md` (product model)
Use this to understand product intent, user-facing mechanics, and behavior scenarios.

Contains:
- conceptual framing of Capsules/Starters/Relationships
- invitation mechanics and edge-case behavior
- relay and trust model from product perspective
- documentation/comment language policy rationale

This document must stay consistent with `specification.md`.

## Recommended Reading Order

1. `specification.md`
2. `hivra-v3.2-conceptual-model.md`

## Update Rules

- Any protocol, invariant, event, or UI contract change must update `specification.md` in the same PR.
- If product behavior/flows are affected, update `hivra-v3.2-conceptual-model.md` in the same PR.
- Keep terminology consistent: Capsule, Starter, Invitation, Relationship, Ledger, Network.
- All product-bound documentation and code comments must be in English.

## Quick PR Checklist

- Architecture/dependency rules still valid
- Invariants still valid
- Event set and payload fields still valid
- UI contract still valid
- Conceptual flows and exceptional cases updated (if behavior changed)
