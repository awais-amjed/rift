//! The second connection a share opens into the call's room.
use livekit::e2ee::key_provider::{KeyProvider, KeyProviderOptions};
use livekit::e2ee::{E2eeOptions, EncryptionType};
use livekit::prelude::*;

/// Join the room this token is for, encrypting with the call's key.
///
/// `with_shared_key` is right here and not in the app: a share publishes and
/// subscribes to nothing, so it never needs anyone else's key — and the app's
/// per-participant mode exists only so a bot can be given a different one.
pub(crate) async fn connect(
    livekit_url: &str,
    livekit_token: &str,
    e2ee_key: &[u8],
    e2ee_key_index: i32,
) -> Result<Room, String> {
    let key_provider =
        KeyProvider::with_shared_key(KeyProviderOptions::default(), e2ee_key.to_vec());
    key_provider.set_shared_key(e2ee_key.to_vec(), e2ee_key_index);

    // `RoomOptions` is non-exhaustive upstream, so it is built and then set
    // rather than written as a literal.
    let mut room_options = RoomOptions::default();
    room_options.encryption = Some(E2eeOptions {
        encryption_type: EncryptionType::Gcm,
        key_provider,
    });

    let (room, _events) = Room::connect(livekit_url, livekit_token, room_options)
        .await
        .map_err(|e| format!("Failed to connect to LiveKit: {e:?}"))?;
    Ok(room)
}

/// Point every cryptor at the slot the room is actually reading.
///
/// The Rust SDK creates a sender's frame cryptor and never sets its key index,
/// so it encrypts into libwebrtc's default slot 0 — while every Rift client
/// looks this identity up at `keyVersion % 16`. The share then publishes
/// happily and decrypts for nobody: the sharer sees "sharing", the room sees a
/// black tile or silence, and nothing anywhere reports an error.
///
/// Called after every track is published, because a cryptor does not exist
/// until its track does.
pub(crate) fn pin_key_index(room: &Room, e2ee_key_index: i32) {
    for (_, cryptor) in room.e2ee_manager().frame_cryptors() {
        cryptor.set_key_index(e2ee_key_index);
    }
}
