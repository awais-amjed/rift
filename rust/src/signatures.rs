//! Ed25519 signature checks: every message a client opens, every row it reads.
//!
//! The `cryptography` package checks them in Dart, on the UI isolate, at a
//! few milliseconds each on a phone, and opening a channel checks a page of
//! them: about 210 ms of a 0.33 s open on an Exynos phone (Nov 12 2026), and
//! long enough in a debug build for Android to say Rift was not responding.
//! Here one costs tens of microseconds, on one of the bridge's worker threads.
//!
//! [verify] is strict: besides the signature equation it refuses a key or an
//! `R` of small order, which no honest key or signature has, and an `S` not
//! below the group order, which Dart refuses too. A browser's Web Crypto,
//! what the web client checks with, refuses the small-order ones as well.

use ed25519_dalek::{Signature, VerifyingKey};

/// Whether `signature` (64 bytes) over `message` is the holder of
/// `public_key`'s (32 bytes). False for wrong lengths and for a key that is
/// not a point on the curve, as for any other failure: the caller only ever
/// needs to know whether it may trust the message.
pub(crate) fn verify(public_key: &[u8], signature: &[u8], message: &[u8]) -> bool {
    let Ok(public_key) = <&[u8; 32]>::try_from(public_key) else {
        return false;
    };
    let Ok(signature) = <&[u8; 64]>::try_from(signature) else {
        return false;
    };
    let Ok(key) = VerifyingKey::from_bytes(public_key) else {
        return false;
    };
    key.verify_strict(message, &Signature::from_bytes(signature))
        .is_ok()
}

#[cfg(test)]
mod tests {
    use super::verify;

    fn hex(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    // RFC 8032 §7.1, TEST 2: what the Dart code is checked against too.
    const KEY: &str = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c";
    const SIG: &str = "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da\
                       085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00";

    #[test]
    fn rfc_8032_vectors_pass() {
        assert!(verify(&hex(KEY), &hex(SIG), &[0x72]));
        // TEST 1: the empty message.
        assert!(verify(
            &hex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"),
            &hex(
                "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155\
                 5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
            ),
            &[],
        ));
    }

    #[test]
    fn any_change_fails() {
        assert!(!verify(&hex(KEY), &hex(SIG), &[0x73]));
        assert!(!verify(&hex(KEY), &hex(SIG), &[0x72, 0x00]));
        let mut sig = hex(SIG);
        sig[0] ^= 1;
        assert!(!verify(&hex(KEY), &sig, &[0x72]));
        let mut key = hex(KEY);
        key[0] ^= 1;
        assert!(!verify(&key, &hex(SIG), &[0x72]));
    }

    #[test]
    fn wrong_lengths_fail_without_panicking() {
        assert!(!verify(&hex(KEY)[..31], &hex(SIG), &[0x72]));
        assert!(!verify(&hex(KEY), &hex(SIG)[..63], &[0x72]));
        assert!(!verify(&[], &[], &[]));
    }

    #[test]
    fn s_not_below_the_group_order_fails() {
        // The same signature with the group order added to S: the equation
        // still holds, and both this and Dart refuse it.
        const L: [u8; 32] = [
            0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9,
            0xde, 0x14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10,
        ];
        let mut sig = hex(SIG);
        let mut carry = 0u16;
        for i in 0..32 {
            let sum = sig[32 + i] as u16 + L[i] as u16 + carry;
            sig[32 + i] = sum as u8;
            carry = sum >> 8;
        }
        assert_eq!(carry, 0);
        assert!(!verify(&hex(KEY), &sig, &[0x72]));
    }

    #[test]
    fn a_small_order_key_fails() {
        // The identity point as a key, with R the identity and S zero: the
        // cofactorless equation holds for every message, so only the
        // small-order check refuses it.
        let mut identity = [0u8; 32];
        identity[0] = 1;
        let mut sig = [0u8; 64];
        sig[..32].copy_from_slice(&identity);
        assert!(!verify(&identity, &sig, b"anything"));
    }
}
