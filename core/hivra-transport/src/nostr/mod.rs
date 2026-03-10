//! Nostr transport adapter

use crate::{Message, Transport, TransportError};
use nostr_sdk::nips::nip04;
use nostr_sdk::prelude::*;
use std::thread;
use std::time::{Duration, Instant};
use tokio::runtime::{Builder, Runtime};

// Use standard DM kind for better relay compatibility.
const APP_EVENT_KIND: Kind = Kind::Custom(4);
const WRITE_RETRY_DELAY_MS: u64 = 1200;
const RELAY_SEND_ATTEMPTS: usize = 2;
const CONNECT_POLL_MS: u64 = 250;
const RECEIVE_LIMIT: usize = 200;

fn looks_like_nip04_content(content: &str) -> bool {
    let mut parts = content.splitn(2, "?iv=");
    let cipher = parts.next().unwrap_or_default();
    let iv = parts.next().unwrap_or_default();

    // NIP-04 requires a 16-byte IV. In base64 that is typically 22-24 chars.
    !cipher.is_empty() && iv.len() >= 22
}

fn extract_auth_challenge(reason: &str) -> Option<String> {
    let needle = "auth-required:";
    let idx = reason.find(needle)?;
    let challenge = reason[idx + needle.len()..].trim();
    if challenge.is_empty() {
        None
    } else {
        Some(challenge.to_string())
    }
}

#[derive(Debug, Clone)]
pub struct NostrConfig {
    pub relays: Vec<String>,
    pub ephemeral: bool,
    pub timeout: u64,
}

impl Default for NostrConfig {
    fn default() -> Self {
        Self {
            relays: vec![
                "wss://nos.lol".into(),
                "wss://relay.damus.io".into(),
                "wss://relay.primal.net".into(),
                "wss://relay.snort.social".into(),
                "wss://relay.nostr.band".into(),
                "wss://relay.current.fyi".into(),
            ],
            ephemeral: true,
            // Keep receive reliable across slower relay handshakes.
            timeout: 8,
        }
    }
}

pub struct NostrTransport {
    runtime: Runtime,
    client: Client,
    keys: Keys,
    public_key: PublicKey,
    timeout_secs: u64,
}

impl NostrTransport {
    pub fn new(config: NostrConfig, secret_key: &[u8; 32]) -> Result<Self, TransportError> {
        eprintln!("[Nostr] Creating transport with external secret key");

        let secret = SecretKey::from_slice(secret_key)
            .map_err(|e| {
                eprintln!("[Nostr] Invalid secret key: {:?}", e);
                TransportError::InvalidKey
            })?;
        let keys = Keys::new(secret);
        let public_key = keys.public_key();

        eprintln!("[Nostr] Public key: {}", public_key.to_bech32().unwrap_or("invalid".into()));

        let runtime = Self::build_runtime()?;
        let client = Self::build_client(&runtime, &config, &keys)?;

        eprintln!("[Nostr] Transport ready");

        Ok(Self {
            runtime,
            client,
            keys,
            public_key,
            timeout_secs: config.timeout,
        })
    }

    pub fn new_with_keys(config: NostrConfig, secret_key: &[u8; 32]) -> Result<Self, TransportError> {
        Self::new(config, secret_key)
    }

    fn build_runtime() -> Result<Runtime, TransportError> {
        Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .map_err(|_| TransportError::ConnectionFailed)
    }

    fn build_client(runtime: &Runtime, config: &NostrConfig, keys: &Keys) -> Result<Client, TransportError> {
        let client = Client::new(keys.clone());
        client.automatic_authentication(true);

        for relay_url in &config.relays {
            eprintln!("[Nostr] Adding relay: {}", relay_url);
            runtime.block_on(client.add_relay(relay_url)).map_err(|e| {
                eprintln!("[Nostr] Failed to add relay {}: {:?}", relay_url, e);
                TransportError::ConnectionFailed
            })?;
        }

        eprintln!("[Nostr] Connecting to relays...");
        runtime.block_on(client.connect());

        if !Self::wait_for_connected_relays(runtime, &client, Duration::from_secs(config.timeout.max(2))) {
            eprintln!("[Nostr] Warning: no relay reached Connected state during init");
        }

        Ok(client)
    }

    fn wait_for_connected_relays(runtime: &Runtime, client: &Client, timeout: Duration) -> bool {
        let deadline = Instant::now() + timeout;

        loop {
            let relays = runtime.block_on(client.relays());
            let connected = relays
                .values()
                .any(|relay| matches!(relay.status(), RelayStatus::Connected));

            if connected {
                return true;
            }

            if Instant::now() >= deadline {
                return false;
            }

            runtime.block_on(client.connect());
            thread::sleep(Duration::from_millis(CONNECT_POLL_MS));
        }
    }

    fn ensure_connected_relays(&self) -> bool {
        Self::wait_for_connected_relays(
            &self.runtime,
            &self.client,
            Duration::from_secs(self.timeout_secs.max(2)),
        )
    }

    pub fn public_key_bytes(&self) -> [u8; 32] {
        self.public_key.to_bytes()
    }

    /// Returns the Nostr event kind used by Hivra messages.
    pub fn event_kind() -> Kind {
        APP_EVENT_KIND
    }

    /// Serializes a transport message into Nostr event content.
    ///
    /// For kind=4 we publish a NIP-04 encrypted DM content.
    pub fn serialize_message(&self, message: &Message) -> Result<String, TransportError> {
        let plaintext = serde_json::to_string(message).map_err(|_| TransportError::EncodingFailed)?;

        if APP_EVENT_KIND == Kind::Custom(4) {
            let recipient = PublicKey::from_slice(&message.to)
                .map_err(|_| TransportError::InvalidKey)?;
            let secret = self.keys.secret_key();
            nip04::encrypt(secret, &recipient, plaintext.as_str())
                .map_err(|_| TransportError::EncodingFailed)
        } else {
            Ok(plaintext)
        }
    }

    /// Builds Nostr tags for a transport message.
    pub fn message_tags(&self, message: &Message) -> Result<Vec<Tag>, TransportError> {
        let recipient_pubkey = PublicKey::from_slice(&message.to)
            .map_err(|e| {
                eprintln!("[Nostr] Invalid recipient pubkey: {:?}", e);
                TransportError::InvalidKey
            })?;

        Ok(vec![Tag::public_key(recipient_pubkey)])
    }

    /// Creates an unsigned `EventBuilder` from a transport message.
    ///
    /// This method exists so upper layers can sign outside of transport,
    /// then submit the fully signed event via `send_event`.
    pub fn event_builder_for_message(&self, message: &Message) -> Result<EventBuilder, TransportError> {
        let content = self.serialize_message(message)?;
        let tags = self.message_tags(message)?;
        Ok(EventBuilder::new(APP_EVENT_KIND, content, tags))
    }

    fn build_signed_event(&self, content: String, tags: Vec<Tag>) -> Result<Event, TransportError> {
        eprintln!("[Nostr] Creating event with kind: {}", APP_EVENT_KIND.as_u16());

        self.runtime
            .block_on(EventBuilder::new(APP_EVENT_KIND, content, tags).sign(&self.keys))
            .map_err(|e| {
            eprintln!("[Nostr] Signing failed: {:?}", e);
            TransportError::EncodingFailed
        })
    }

    fn encode_message(&self, message: Message) -> Result<Event, TransportError> {
        eprintln!("[Nostr] Encoding message to: {:?}", &message.to[..4]);

        let content = self.serialize_message(&message)?;
        eprintln!("[Nostr] Message content: {}", content);

        let tags = self.message_tags(&message)?;
        let event = self.build_signed_event(content, tags)?;

        eprintln!("[Nostr] Event ID: {}", event.id.to_hex());
        Ok(event)
    }

    /// Prepares a signed Nostr event using an external signer.
    ///
    /// This is the migration path toward keeping signing in upper layers.
    pub fn prepare_event<S>(&self, message: &Message, signer: S) -> Result<Event, TransportError>
    where
        S: FnOnce(EventBuilder) -> Result<Event, TransportError>,
    {
        let builder = self.event_builder_for_message(message)?;
        signer(builder)
    }

    /// Sends a message using an externally signed Nostr event.
    pub fn send_prepared<S>(&self, message: &Message, signer: S) -> Result<(), TransportError>
    where
        S: FnOnce(EventBuilder) -> Result<Event, TransportError>,
    {
        let event = self.prepare_event(message, signer)?;
        self.send_event(event)
    }

    pub fn send_event(&self, event: Event) -> Result<(), TransportError> {
        if !self.ensure_connected_relays() {
            eprintln!("[Nostr] No connected relays available before publish");
            return Err(TransportError::SendFailed);
        }

        let relays = self.runtime.block_on(self.client.relays());

        if relays.is_empty() {
            eprintln!("[Nostr] No relays available for publish");
            return Err(TransportError::SendFailed);
        }

        let mut any_success = false;

        for relay in relays.into_values() {
            let relay_url = relay.url().to_string();

            if !matches!(relay.status(), RelayStatus::Connected) {
                eprintln!("[Nostr] Relay {} skipped: status {}", relay_url, relay.status());
                continue;
            }

            let mut published = false;

            for attempt in 1..=RELAY_SEND_ATTEMPTS {
                match self.runtime.block_on(relay.send_event(event.clone())) {
                    Ok(id) => {
                        eprintln!(
                            "[Nostr] Relay {} accepted event on attempt {}/{}: {}",
                            relay_url,
                            attempt,
                            RELAY_SEND_ATTEMPTS,
                            id.to_hex()
                        );
                        published = true;
                        any_success = true;
                        break;
                    }
                    Err(err) => {
                        let reason = err.to_string();
                        eprintln!(
                            "[Nostr] Relay {} reject on attempt {}/{}: {}",
                            relay_url,
                            attempt,
                            RELAY_SEND_ATTEMPTS,
                            reason
                        );

                        if attempt < RELAY_SEND_ATTEMPTS {
                            if let Some(challenge) = extract_auth_challenge(&reason) {
                                eprintln!("[Nostr] Relay {} requested NIP-42 auth, trying AUTH", relay_url);
                                match self
                                    .runtime
                                    .block_on(self.client.auth(challenge, relay.url().clone()))
                                {
                                    Ok(()) => {
                                        eprintln!("[Nostr] Relay {} auth succeeded", relay_url);
                                    }
                                    Err(auth_err) => {
                                        eprintln!(
                                            "[Nostr] Relay {} auth failed: {}",
                                            relay_url,
                                            auth_err
                                        );
                                        break;
                                    }
                                }
                            } else {
                                // Keep old reconnect behavior for transient relay issues.
                                self.runtime.block_on(self.client.connect());
                                thread::sleep(Duration::from_millis(WRITE_RETRY_DELAY_MS));
                            }
                        }
                    }
                }
            }

            if !published {
                eprintln!("[Nostr] Relay {} did not accept event", relay_url);
            }
        }

        if any_success {
            eprintln!("[Nostr] Message published to at least one relay");
            Ok(())
        } else {
            eprintln!("[Nostr] Send failed: no relay accepted event");
            Err(TransportError::SendFailed)
        }
    }

    fn decode_event(&self, event: Event) -> Result<Message, TransportError> {
        if event.kind != APP_EVENT_KIND {
            return Err(TransportError::InvalidMessage);
        }

        let content = if APP_EVENT_KIND == Kind::Custom(4) {
            // Only attempt DM decryption for events addressed to our pubkey.
            let addressed_to_me = event.tags.public_keys().any(|pk| *pk == self.public_key);
            if !addressed_to_me {
                return Err(TransportError::InvalidMessage);
            }

            if !looks_like_nip04_content(&event.content) {
                return Err(TransportError::DecodingFailed);
            }

            let secret = self.keys.secret_key();
            // kind=4 content is NIP-04 ciphertext encrypted by the sender for our pubkey.
            nip04::decrypt(secret, &event.pubkey, &event.content)
                .map_err(|_| TransportError::DecodingFailed)?
        } else {
            event.content
        };

        let message: Message = serde_json::from_str(&content)
            .map_err(|_| TransportError::InvalidMessage)?;
        Ok(message)
    }
}

impl Transport for NostrTransport {
    fn send(&self, message: Message) -> Result<(), TransportError> {
        eprintln!("[Nostr] Sending message...");
        let event = self.encode_message(message)?;
        self.send_event(event)
    }

    fn receive(&self) -> Result<Vec<Message>, TransportError> {
        eprintln!("[Nostr] Receiving messages...");

        if !self.ensure_connected_relays() {
            eprintln!("[Nostr] No connected relays available for receive");
            return Ok(Vec::new());
        }

        // Query only DMs where we're in the `p` tag; this avoids global kind=4 noise.
        let filter = Filter::new()
            .kind(APP_EVENT_KIND)
            .pubkey(self.public_key)
            .limit(RECEIVE_LIMIT);
        
        let events = self.runtime.block_on(
            self.client
                .fetch_events(vec![filter], Some(Duration::from_secs(self.timeout_secs))),
        )
            .map_err(|e| {
                eprintln!("[Nostr] Receive failed: {:?}", e);
                TransportError::ReceiveFailed
            })?;
        
        eprintln!("[Nostr] Received {} events", events.len());
        
        let mut messages = Vec::new();
        for event in events {
            if let Ok(msg) = self.decode_event(event) {
                messages.push(msg);
            }
        }
        Ok(messages)
    }

    fn is_connected(&self) -> bool {
        !self.runtime.block_on(self.client.relays()).is_empty()
    }

    fn name(&self) -> &'static str {
        "nostr"
    }
}
