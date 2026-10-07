//! AES-256-GCM for blobs: attachments and saved conversations.
//!
//! The format is the one the Dart code has always written — the ciphertext
//! with its 16-byte tag appended, under a 12-byte nonce kept beside it — so a
//! blob sealed here opens in Dart and the other way round. Only the speed
//! changes: the `cryptography` package does AES in Dart on the UI isolate,
//! which froze the window for about 4 s on a 50 MB file, and this runs on the
//! CPU's AES instructions on one of the bridge's worker threads.
//!
//! A big file is sealed a chunk at a time instead ([seal_chunk]), so no copy
//! of it ever has to fit in memory: the STREAM construction from aead's
//! `stream` module, which puts each chunk's position and a last-chunk flag in
//! its nonce. Chunks cannot be reordered, dropped or cut off at the end
//! without a tag failing.
//!
//! An attachment sent unencrypted has no tag, so it carries a SHA-256 of its
//! bytes inside the sealed message instead: the server can read it, but not
//! swap it. [digest] is that hash, and [StreamDigest] the same hash fed a
//! piece at a time.

use aes_gcm::aead::stream::{NewStream, StreamBE32, StreamPrimitive};
use aes_gcm::aead::{AeadInPlace, KeyInit};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use sha2::{Digest, Sha256};

const KEY_LEN: usize = 32;
const NONCE_LEN: usize = 12;
const TAG_LEN: usize = 16;
/// What STREAM leaves of the nonce: 12 bytes less a 4-byte position and a
/// 1-byte last-chunk flag.
const PREFIX_LEN: usize = 7;

fn cipher(key: &[u8], nonce: &[u8]) -> Result<Aes256Gcm, String> {
    if key.len() != KEY_LEN {
        return Err(format!("A blob key is {KEY_LEN} bytes, not {}", key.len()));
    }
    if nonce.len() != NONCE_LEN {
        return Err(format!("A blob nonce is {NONCE_LEN} bytes, not {}", nonce.len()));
    }
    Ok(Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key)))
}

/// Encrypts `data` in place and appends the tag.
pub(crate) fn seal(key: &[u8], nonce: &[u8], mut data: Vec<u8>) -> Result<Vec<u8>, String> {
    let cipher = cipher(key, nonce)?;
    // The tag would otherwise make the vector reallocate, which on a big file
    // is a second copy of it.
    data.reserve_exact(TAG_LEN);
    cipher
        .encrypt_in_place(Nonce::from_slice(nonce), b"", &mut data)
        .map_err(|_| "Could not encrypt the blob".to_string())?;
    Ok(data)
}

/// Checks the tag on `sealed` and decrypts it in place. Fails on a wrong key
/// or nonce and on any change to the bytes.
pub(crate) fn open(key: &[u8], nonce: &[u8], mut sealed: Vec<u8>) -> Result<Vec<u8>, String> {
    let cipher = cipher(key, nonce)?;
    if sealed.len() < TAG_LEN {
        return Err("The blob is shorter than its tag".to_string());
    }
    cipher
        .decrypt_in_place(Nonce::from_slice(nonce), b"", &mut sealed)
        .map_err(|_| "The blob did not decrypt: wrong key, or it was changed".to_string())?;
    Ok(sealed)
}

fn stream(key: &[u8], prefix: &[u8]) -> Result<StreamBE32<Aes256Gcm>, String> {
    if prefix.len() != PREFIX_LEN {
        return Err(format!("A stream nonce is {PREFIX_LEN} bytes, not {}", prefix.len()));
    }
    // A full nonce's worth of checks on the key, then the prefix in its place.
    let aead = cipher(key, &[0; NONCE_LEN])?;
    Ok(StreamBE32::from_aead(aead, prefix.into()))
}

/// Encrypts chunk `position` of a file sealed under `key` and the 7-byte
/// nonce `prefix`, marking it the last when `last`. Returns it with its tag.
pub(crate) fn seal_chunk(
    key: &[u8],
    prefix: &[u8],
    position: u32,
    last: bool,
    mut data: Vec<u8>,
) -> Result<Vec<u8>, String> {
    data.reserve_exact(TAG_LEN);
    stream(key, prefix)?
        .encrypt_in_place(position, last, b"", &mut data)
        .map_err(|_| "Could not encrypt the chunk".to_string())?;
    Ok(data)
}

/// Opens what [seal_chunk] made. Fails if the chunk was changed, moved, or is
/// not where the stream ends when `last` says it is.
pub(crate) fn open_chunk(
    key: &[u8],
    prefix: &[u8],
    position: u32,
    last: bool,
    mut sealed: Vec<u8>,
) -> Result<Vec<u8>, String> {
    if sealed.len() < TAG_LEN {
        return Err("The chunk is shorter than its tag".to_string());
    }
    stream(key, prefix)?
        .decrypt_in_place(position, last, b"", &mut sealed)
        .map_err(|_| "The chunk did not decrypt: wrong key, moved, or changed".to_string())?;
    Ok(sealed)
}

/// SHA-256 of `data`.
pub(crate) fn digest(data: &[u8]) -> Vec<u8> {
    Sha256::digest(data).to_vec()
}

/// SHA-256 over pieces given one after another. Finished once; a second
/// [StreamDigest::finish] is an error rather than the hash of nothing.
pub(crate) struct StreamDigest(Option<Sha256>);

impl StreamDigest {
    pub(crate) fn new() -> Self {
        Self(Some(Sha256::new()))
    }

    pub(crate) fn update(&mut self, data: &[u8]) -> Result<(), String> {
        self.0
            .as_mut()
            .ok_or_else(|| "The digest is already finished".to_string())?
            .update(data);
        Ok(())
    }

    pub(crate) fn finish(&mut self) -> Result<Vec<u8>, String> {
        let hasher = self
            .0
            .take()
            .ok_or_else(|| "The digest is already finished".to_string())?;
        Ok(hasher.finalize().to_vec())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    // Test case 15 of the GCM specification (AES-256, 96-bit nonce, no
    // associated data), which test/chat_crypto_test.dart checks the Dart side
    // against too.
    const KEY: &str = "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308";
    const NONCE: &str = "cafebabefacedbaddecaf888";
    const PLAIN: &str = "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72\
                         1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255";
    const SEALED: &str = "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa\
                          8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad\
                          b094dac5d93471bdec1a502270e3cc6c";

    #[test]
    fn seals_the_specification_vector() {
        let sealed = seal(&hex(KEY), &hex(NONCE), hex(PLAIN)).unwrap();
        assert_eq!(sealed, hex(SEALED));
    }

    #[test]
    fn opens_the_specification_vector() {
        let plain = open(&hex(KEY), &hex(NONCE), hex(SEALED)).unwrap();
        assert_eq!(plain, hex(PLAIN));
    }

    #[test]
    fn refuses_a_changed_byte() {
        let mut sealed = hex(SEALED);
        sealed[3] ^= 1;
        assert!(open(&hex(KEY), &hex(NONCE), sealed).is_err());
    }

    #[test]
    fn refuses_the_wrong_key() {
        let mut key = hex(KEY);
        key[0] ^= 1;
        assert!(open(&key, &hex(NONCE), hex(SEALED)).is_err());
    }

    #[test]
    fn refuses_a_short_key_or_nonce() {
        assert!(seal(&[0; 16], &hex(NONCE), vec![1]).is_err());
        assert!(seal(&hex(KEY), &[0; 8], vec![1]).is_err());
        assert!(open(&hex(KEY), &hex(NONCE), vec![0; 4]).is_err());
    }

    // FIPS 180-2's "abc", which the Dart side checks too.
    #[test]
    fn digests_the_specification_vector() {
        assert_eq!(
            digest(b"abc"),
            hex("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        );
    }

    // Computed with Python's `cryptography` AES-GCM under the nonce STREAM
    // describes (prefix, big-endian position, last flag), so this proves the
    // layout and not just a round trip. test/chat_crypto_test.dart holds the
    // Dart side to the same two chunks.
    const PREFIX: &str = "cafebabefacedb";
    const CHUNK0: &str = "f44fe62a9eb368516d28707c631e4d8cd1463a2cea30d0581c72";
    const CHUNK1_LAST: &str = "5146419d31b4a19d92262648ad0aae4f35230ba7";

    #[test]
    fn seals_chunks_with_their_place_in_the_nonce() {
        let key = hex(KEY);
        let prefix = hex(PREFIX);
        assert_eq!(
            seal_chunk(&key, &prefix, 0, false, b"chunk zero".to_vec()).unwrap(),
            hex(CHUNK0)
        );
        assert_eq!(seal_chunk(&key, &prefix, 1, true, b"last".to_vec()).unwrap(), hex(CHUNK1_LAST));
        assert_eq!(open_chunk(&key, &prefix, 1, true, hex(CHUNK1_LAST)).unwrap(), b"last");
    }

    #[test]
    fn a_chunk_opens_only_where_it_was_sealed() {
        let key = hex(KEY);
        let prefix = hex(PREFIX);
        // Moved to another position.
        assert!(open_chunk(&key, &prefix, 1, false, hex(CHUNK0)).is_err());
        // A file cut short: its new end was not sealed as the last chunk.
        assert!(open_chunk(&key, &prefix, 0, true, hex(CHUNK0)).is_err());
        // A last chunk with more said to follow it.
        assert!(open_chunk(&key, &prefix, 1, false, hex(CHUNK1_LAST)).is_err());
        assert!(seal_chunk(&key, &[0; 12], 0, true, vec![1]).is_err());
    }

    #[test]
    fn digests_in_pieces_as_in_one() {
        let mut stream = StreamDigest::new();
        stream.update(b"a").unwrap();
        stream.update(b"bc").unwrap();
        assert_eq!(stream.finish().unwrap(), digest(b"abc"));
        assert!(stream.finish().is_err());
        assert!(stream.update(b"d").is_err());
    }

    #[test]
    fn seals_an_empty_blob_as_a_tag() {
        let sealed = seal(&hex(KEY), &hex(NONCE), Vec::new()).unwrap();
        assert_eq!(sealed.len(), TAG_LEN);
        assert!(open(&hex(KEY), &hex(NONCE), sealed).unwrap().is_empty());
    }
}
