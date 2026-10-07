//! Sealing and opening attachment blobs off the UI thread
//! (`src/blob_cipher.rs`). Not `sync`: each call runs on a worker thread, so
//! a big file costs the window nothing.

use std::sync::Mutex;

use crate::blob_cipher::StreamDigest;

/// Encrypts `data` with AES-256-GCM under `key` (32 bytes) and `nonce`
/// (12 bytes). Returns the ciphertext with its tag appended.
pub fn seal_blob(key: Vec<u8>, nonce: Vec<u8>, data: Vec<u8>) -> Result<Vec<u8>, String> {
    crate::blob_cipher::seal(&key, &nonce, data)
}

/// Decrypts what [seal_blob] made. Fails on a wrong key and on any change to
/// the bytes.
pub fn open_blob(key: Vec<u8>, nonce: Vec<u8>, sealed: Vec<u8>) -> Result<Vec<u8>, String> {
    crate::blob_cipher::open(&key, &nonce, sealed)
}

/// SHA-256 of `data`: what an attachment sent unencrypted is checked against.
pub fn digest_blob(data: Vec<u8>) -> Vec<u8> {
    crate::blob_cipher::digest(&data)
}

/// Encrypts chunk `position` of a file sealed a chunk at a time, under `key`
/// and the 7-byte nonce `prefix`; `last` marks the final chunk. Returns the
/// chunk with its tag appended.
pub fn seal_blob_chunk(
    key: Vec<u8>,
    prefix: Vec<u8>,
    position: u32,
    last: bool,
    data: Vec<u8>,
) -> Result<Vec<u8>, String> {
    crate::blob_cipher::seal_chunk(&key, &prefix, position, last, data)
}

/// Decrypts what [seal_blob_chunk] made, at the same `position` and `last`.
pub fn open_blob_chunk(
    key: Vec<u8>,
    prefix: Vec<u8>,
    position: u32,
    last: bool,
    sealed: Vec<u8>,
) -> Result<Vec<u8>, String> {
    crate::blob_cipher::open_chunk(&key, &prefix, position, last, sealed)
}

/// SHA-256 over a file read a piece at a time, for one sent unencrypted.
pub struct BlobHasher {
    inner: Mutex<StreamDigest>,
}

impl BlobHasher {
    #[flutter_rust_bridge::frb(sync)]
    pub fn new() -> Self {
        Self { inner: Mutex::new(StreamDigest::new()) }
    }

    pub fn update(&self, data: Vec<u8>) -> Result<(), String> {
        self.inner.lock().map_err(|e| e.to_string())?.update(&data)
    }

    /// The hash of everything given. Once only.
    pub fn finish(&self) -> Result<Vec<u8>, String> {
        self.inner.lock().map_err(|e| e.to_string())?.finish()
    }
}
