//! Whether a release feed was signed with Rift's release key.
//!
//! A feed (`releases.<channel>.json`, written by `vpk pack`) lists every
//! package of a release with its size and SHA-256, and Velopack refuses a
//! download that does not match. So the feed is the one file whose
//! authenticity matters — but it comes from the same GitHub release as the
//! packages, and anyone able to publish there could publish both. The
//! signature beside it (`releases.<channel>.json.sig`) is made on the
//! release manager's own machine (`scripts/sign_release.sh`), with a key
//! that is never uploaded, so a feed nobody signed offers nothing to update
//! to.
//!
//! The signed message is a domain tag, the channel and the feed's bytes:
//!
//! ```text
//! rift-update-feed-v1\n<channel>\n<feed>
//! ```
//!
//! The channel is in it so the Linux feed cannot be offered as the Windows
//! one, and the tag so no other Ed25519 signature made with this key could
//! pass for a feed's.

use base64::Engine;
use ring::signature::{UnparsedPublicKey, ED25519};

const DOMAIN: &[u8] = b"rift-update-feed-v1\n";

/// The public half of each key a feed may be signed with, base64 of the 32
/// raw Ed25519 bytes (`scripts/release_key.sh public`). More than one only
/// while a key is being replaced: a release signed with the new one reaches
/// only clients that already list it.
pub(crate) const RELEASE_KEYS: &[&str] = &["DrVqSjvcede5atKmapT8/USBwgl5ReVJQgy4QvrtXgA="];

/// The bytes the signature covers.
pub(crate) fn message(channel: &str, feed: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(DOMAIN.len() + channel.len() + 1 + feed.len());
    out.extend_from_slice(DOMAIN);
    out.extend_from_slice(channel.as_bytes());
    out.push(b'\n');
    out.extend_from_slice(feed);
    out
}

/// True when `signature` (base64, surrounding whitespace ignored) is a valid
/// signature of `feed` on `channel` by one of `keys` (base64 public keys).
pub(crate) fn verify(channel: &str, feed: &[u8], signature: &str, keys: &[&str]) -> bool {
    let b64 = base64::engine::general_purpose::STANDARD;
    let Ok(signature) = b64.decode(signature.trim()) else {
        return false;
    };
    let message = message(channel, feed);
    keys.iter().any(|key| {
        b64.decode(key)
            .is_ok_and(|key| UnparsedPublicKey::new(&ED25519, key).verify(&message, &signature).is_ok())
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use ring::rand::SystemRandom;
    use ring::signature::{Ed25519KeyPair, KeyPair};

    fn b64(bytes: &[u8]) -> String {
        base64::engine::general_purpose::STANDARD.encode(bytes)
    }

    fn key_pair() -> Ed25519KeyPair {
        let pkcs8 = Ed25519KeyPair::generate_pkcs8(&SystemRandom::new()).unwrap();
        Ed25519KeyPair::from_pkcs8(pkcs8.as_ref()).unwrap()
    }

    fn sign(pair: &Ed25519KeyPair, channel: &str, feed: &[u8]) -> String {
        b64(pair.sign(&message(channel, feed)).as_ref())
    }

    const FEED: &[u8] = br#"{"Assets":[{"FileName":"CodingFries.Rift-1.5.0-full.nupkg"}]}"#;

    #[test]
    fn a_signed_feed_passes() {
        let pair = key_pair();
        let key = b64(pair.public_key().as_ref());
        let signature = sign(&pair, "win", FEED);
        assert!(verify("win", FEED, &format!("{signature}\n"), &[&key]));
    }

    #[test]
    fn any_listed_key_will_do() {
        let (old, new) = (key_pair(), key_pair());
        let keys = [b64(old.public_key().as_ref()), b64(new.public_key().as_ref())];
        let keys: Vec<&str> = keys.iter().map(String::as_str).collect();
        assert!(verify("win", FEED, &sign(&new, "win", FEED), &keys));
    }

    #[test]
    fn a_changed_feed_fails() {
        let pair = key_pair();
        let key = b64(pair.public_key().as_ref());
        let signature = sign(&pair, "win", FEED);
        let mut changed = FEED.to_vec();
        changed[20] ^= 1;
        assert!(!verify("win", &changed, &signature, &[&key]));
    }

    #[test]
    fn another_channels_feed_fails() {
        let pair = key_pair();
        let key = b64(pair.public_key().as_ref());
        assert!(!verify("win", FEED, &sign(&pair, "linux", FEED), &[&key]));
    }

    #[test]
    fn another_key_fails() {
        let (signer, other) = (key_pair(), key_pair());
        let key = b64(other.public_key().as_ref());
        assert!(!verify("win", FEED, &sign(&signer, "win", FEED), &[&key]));
    }

    #[test]
    fn no_keys_and_junk_fail() {
        let pair = key_pair();
        let signature = sign(&pair, "win", FEED);
        assert!(!verify("win", FEED, &signature, &[]));
        let key = b64(pair.public_key().as_ref());
        assert!(!verify("win", FEED, "not base64!", &[&key]));
        assert!(!verify("win", FEED, &signature, &["AAAA"]));
    }

    /// A signature made the way `scripts/sign_release.sh` makes one — the
    /// message assembled with printf and signed by `openssl pkeyutl -rawin` —
    /// with a throwaway key, so the script and this check cannot drift apart.
    #[test]
    fn the_signing_script_s_format_passes() {
        const KEY: &str = "jbI0V/Fs+5iQKFgiGVhmGRslfuAA7J5a18SfGoPrquc=";
        const SIGNATURE: &str =
            "6Cu8HIGuRnfyEHi2AXLTf1PoEg0sR7RCobM7UsbawG5XZry++Wkw9Mo+iukL9mB+SqqD7YPZMPvjzy4X+NlvAg==";
        assert!(verify("linux", FEED, SIGNATURE, &[KEY]));
    }
}
