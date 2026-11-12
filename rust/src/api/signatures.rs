//! Checking message signatures off the UI thread (`src/signatures.rs`). Not
//! `sync`: each call runs on a worker thread, so a page of them costs the
//! window nothing.

/// Whether `signature` (64 bytes) over `message` was made with the key whose
/// public half is `public_key` (32 bytes). False for anything malformed.
pub fn verify_ed25519(public_key: Vec<u8>, signature: Vec<u8>, message: Vec<u8>) -> bool {
    crate::signatures::verify(&public_key, &signature, &message)
}
