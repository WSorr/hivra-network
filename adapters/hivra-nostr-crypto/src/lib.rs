//! Nostr secp256k1 implementation of Hivra Engine `CryptoProvider`.

use hivra_engine::CryptoProvider;
use secp256k1::ecdh::SharedSecret;
use secp256k1::schnorr::Signature as SchnorrSignature;
use secp256k1::{Keypair, Message, Parity, Secp256k1, SecretKey, XOnlyPublicKey};

/// Errors returned by `NostrCryptoProvider`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NostrCryptoError {
    InvalidMessageLength(usize),
    InvalidPublicKey,
    InvalidSignature,
    VerifyFailed,
    InvalidSecretKey,
    EcdhFailed,
}

/// Crypto provider for Nostr/Schnorr over secp256k1.
pub struct NostrCryptoProvider {
    secp: Secp256k1<secp256k1::All>,
}

impl NostrCryptoProvider {
    /// Creates a new provider instance.
    pub fn new() -> Self {
        Self {
            secp: Secp256k1::new(),
        }
    }

    fn parse_message(msg: &[u8]) -> Result<Message, NostrCryptoError> {
        if msg.len() != 32 {
            return Err(NostrCryptoError::InvalidMessageLength(msg.len()));
        }

        Message::from_digest_slice(msg)
            .map_err(|_| NostrCryptoError::InvalidMessageLength(msg.len()))
    }
}

impl Default for NostrCryptoProvider {
    fn default() -> Self {
        Self::new()
    }
}

impl CryptoProvider for NostrCryptoProvider {
    type Error = NostrCryptoError;

    fn verify(&self, msg: &[u8], pubkey: &[u8; 32], sig: &[u8; 64]) -> Result<(), Self::Error> {
        let message = Self::parse_message(msg)?;
        let xonly = XOnlyPublicKey::from_slice(pubkey)
            .map_err(|_| NostrCryptoError::InvalidPublicKey)?;
        let signature = SchnorrSignature::from_slice(sig)
            .map_err(|_| NostrCryptoError::InvalidSignature)?;

        self.secp
            .verify_schnorr(&signature, &message, &xonly)
            .map_err(|_| NostrCryptoError::VerifyFailed)
    }

    fn sign(&self, msg: &[u8], privkey: &[u8; 32]) -> Result<[u8; 64], Self::Error> {
        let message = Self::parse_message(msg)?;
        let secret = SecretKey::from_slice(privkey).map_err(|_| NostrCryptoError::InvalidSecretKey)?;
        let keypair = Keypair::from_secret_key(&self.secp, &secret);
        let signature = self.secp.sign_schnorr_no_aux_rand(&message, &keypair);

        let mut out = [0u8; 64];
        out.copy_from_slice(signature.as_ref());
        Ok(out)
    }

    fn ecdh(&self, privkey: &[u8; 32], pubkey: &[u8; 32]) -> Result<[u8; 32], Self::Error> {
        let secret = SecretKey::from_slice(privkey).map_err(|_| NostrCryptoError::InvalidSecretKey)?;
        let xonly = XOnlyPublicKey::from_slice(pubkey)
            .map_err(|_| NostrCryptoError::InvalidPublicKey)?;
        let public = secp256k1::PublicKey::from_x_only_public_key(xonly, Parity::Even);
        let shared = SharedSecret::new(&public, &secret);

        Ok(shared.secret_bytes())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sign_and_verify_roundtrip() {
        let provider = NostrCryptoProvider::new();
        let privkey = [7u8; 32];
        let secret = SecretKey::from_slice(&privkey).expect("valid secret key");
        let keypair = Keypair::from_secret_key(&Secp256k1::new(), &secret);
        let (xonly, _) = XOnlyPublicKey::from_keypair(&keypair);

        let message = [9u8; 32];
        let signature = provider.sign(&message, &privkey).expect("signature");
        provider
            .verify(&message, &xonly.serialize(), &signature)
            .expect("verification succeeds");
    }

    #[test]
    fn reject_non_32_byte_message() {
        let provider = NostrCryptoProvider::new();
        let err = provider.sign(&[1u8; 31], &[7u8; 32]).expect_err("must fail");
        assert_eq!(err, NostrCryptoError::InvalidMessageLength(31));
    }
}
