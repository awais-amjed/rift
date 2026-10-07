//! Sealing and opening attachment blobs off the UI thread
//! (`src/blob_cipher.rs`). Not `sync`: each call runs on a worker thread, so
//! a big file costs the window nothing.

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
