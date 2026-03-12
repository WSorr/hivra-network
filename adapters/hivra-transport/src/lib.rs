//! Hivra Transport Layer
//!
//! Abstract transport interface for sending and receiving messages.
//! Supports multiple transport implementations (Nostr, Matrix, BLE, etc.)

#![cfg_attr(not(any(test, feature = "std")), no_std)]

extern crate alloc;

use alloc::string::String;
use alloc::vec::Vec;
use serde::{Deserialize, Serialize};

pub mod nostr;

/// Transport errors
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransportError {
    NotImplemented,
    ConnectionFailed,
    SendFailed,
    ReceiveFailed,
    InvalidMessage,
    EncodingFailed,
    DecodingFailed,
    InvalidKey,
    Timeout,
    Other(String),
}

/// Message format for transport layer
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Message {
    /// Sender public key
    pub from: [u8; 32],
    
    /// Recipient public key
    pub to: [u8; 32],
    
    /// Message kind (event type)
    pub kind: u32,
    
    /// Message payload (serialized event)
    pub payload: Vec<u8>,
    
    /// Timestamp
    pub timestamp: u64,
    
    /// Optional invitation ID
    pub invitation_id: Option<[u8; 32]>,
}

/// Transport trait - all transport implementations must implement this
pub trait Transport: Send + Sync {
    /// Send a message
    fn send(&self, message: Message) -> Result<(), TransportError>;
    
    /// Receive messages
    fn receive(&self) -> Result<Vec<Message>, TransportError>;
    
    /// Check if transport is connected
    fn is_connected(&self) -> bool;
    
    /// Get transport name
    fn name(&self) -> &'static str;
}

/// Transport manager that can use multiple transports
pub struct TransportManager {
    transports: Vec<Box<dyn Transport>>,
}

impl TransportManager {
    /// Create new transport manager
    pub fn new() -> Self {
        Self {
            transports: Vec::new(),
        }
    }
    
    /// Add a transport
    pub fn add_transport(&mut self, transport: Box<dyn Transport>) {
        self.transports.push(transport);
    }
    
    /// Send message via all transports
    pub fn send(&self, message: Message) -> Result<(), TransportError> {
        let mut last_error = None;
        
        for transport in &self.transports {
            match transport.send(message.clone()) {
                Ok(()) => return Ok(()),
                Err(e) => last_error = Some(e),
            }
        }
        
        Err(last_error.unwrap_or(TransportError::SendFailed))
    }
    
    /// Receive messages from all transports
    pub fn receive(&self) -> Result<Vec<Message>, TransportError> {
        let mut all_messages = Vec::new();
        
        for transport in &self.transports {
            if let Ok(messages) = transport.receive() {
                all_messages.extend(messages);
            }
        }
        
        Ok(all_messages)
    }
    
    /// Get list of connected transports
    pub fn connected_transports(&self) -> Vec<&'static str> {
        self.transports
            .iter()
            .filter(|t| t.is_connected())
            .map(|t| t.name())
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    struct MockTransport {
        name: &'static str,
        connected: bool,
    }
    
    impl Transport for MockTransport {
        fn send(&self, _message: Message) -> Result<(), TransportError> {
            Ok(())
        }
        
        fn receive(&self) -> Result<Vec<Message>, TransportError> {
            Ok(Vec::new())
        }
        
        fn is_connected(&self) -> bool {
            self.connected
        }
        
        fn name(&self) -> &'static str {
            self.name
        }
    }
    
    #[test]
    fn test_transport_manager() {
        let mut manager = TransportManager::new();
        
        let transport = Box::new(MockTransport {
            name: "mock",
            connected: true,
        });
        
        manager.add_transport(transport);
        assert_eq!(manager.connected_transports(), vec!["mock"]);
    }
}
