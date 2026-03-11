use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::ptr;
use std::sync::Mutex;

use futures::executor::block_on;
use hivra_core::{
    capsule::{Capsule, CapsuleState, CapsuleType},
    event::{Event, EventKind},
    event_payloads::{
        CapsuleCreatedPayload, EventPayload, InvitationAcceptedPayload, InvitationRejectedPayload,
        InvitationSentPayload, RejectReason, StarterBurnedPayload, StarterCreatedPayload,
    },
    Ledger, Network, PubKey, Signature, StarterId, StarterKind, Timestamp,
};
use hivra_engine::{
    CryptoProvider, Engine, EngineConfig, IncomingEffect, PreparedEvent, RandomSource,
    SecureKeyStore, TimeSource,
};
use hivra_keystore::{
    delete_seed, derive_nostr_keypair, load_seed, mnemonic_to_seed, seed_exists, seed_to_mnemonic,
    store_seed, Seed,
};
use hivra_nostr_crypto::NostrCryptoProvider;
use hivra_transport::nostr::{NostrConfig, NostrTransport};
use hivra_transport::{Message, Transport, TransportError};
use nostr_sdk::prelude::{Keys, SecretKey};
use once_cell::sync::Lazy;
use rand::RngCore;
use serde_json;
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};

mod capsule_api;
mod ffi_support;
mod invitation_api;
mod invitation_support;
mod ledger_api;
mod runtime_support;
mod seed_api;
mod selfcheck_api;

pub use ffi_support::FfiBytes;
pub(crate) use invitation_support::{
    finalize_local_acceptance, find_invitation_sent_in_runtime,
    project_effects_from_invitation_rejected, project_relationship_from_invitation_accepted,
    resolve_local_acceptance_plan,
};
pub(crate) use runtime_support::{
    append_prepared_event, append_runtime_event, append_runtime_event_with_signer, build_engine,
    capsule_network, clear_runtime_state, current_capsule_state, derive_nostr_public_key,
    derive_starter_id, derive_starter_nonce, event_exists_in_runtime,
    event_exists_in_runtime_with_signer, event_kind_from_u8, export_runtime_ledger,
    find_starter_kind_by_id_in_runtime, import_runtime_ledger, init_runtime_state,
    starter_kind_from_slot, FfiEngine, RUNTIME,
};

#[cfg(test)]
mod tests;
