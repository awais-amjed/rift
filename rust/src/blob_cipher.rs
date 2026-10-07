//! AES-256-GCM for blobs: attachments and saved conversations.
//!
//! The format is the one the Dart code has always written — the ciphertext
//! with its 16-byte tag appended, under a 12-byte nonce kept beside it — so a
//! blob sealed here opens in Dart and the other way round. Only the speed
//! changes: the `cryptography` package does AES in Dart on the UI isolate,
//! which froze the window for about 4 s on a 50 MB file, and this runs on the
//! CPU's AES instructions on one of the bridge's worker threads.
//!
//! An attachment sent unencrypted has no tag, so it carries a SHA-256 of its
//! bytes inside the sealed message instead: the server can read it, but not
//! swap it. [digest] is that hash, here for the same reason the cipher is.

use aes_gcm::aead::{AeadInPlace, KeyInit};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use sha2::{Digest, Sha256};

const KEY_LEN: usize = 32;
const NONCE_LEN: usize = 12;
const TAG_LEN: usize = 16;

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

/// SHA-256 of `data`.
pub(crate) fn digest(data: &[u8]) -> Vec<u8> {
    Sha256::digest(data).to_vec()
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

    #[test]
    fn seals_an_empty_blob_as_a_tag() {
        let sealed = seal(&hex(KEY), &hex(NONCE), Vec::new()).unwrap();
        assert_eq!(sealed.len(), TAG_LEN);
        assert!(open(&hex(KEY), &hex(NONCE), sealed).unwrap().is_empty());
    }
}
