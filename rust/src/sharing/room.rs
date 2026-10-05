//! The second connection a share opens into the call's room.
use livekit::e2ee::key_provider::{KeyProvider, KeyProviderOptions};
use livekit::e2ee::manager::E2eeManager;
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
    // While nobody watches the share, the server tells it to stop sending
    // the picture, and libwebrtc stops encoding it.
    room_options.dynacast = true;
    room_options.encryption = Some(E2eeOptions {
        encryption_type: EncryptionType::Gcm,
        key_provider,
    });

    let (room, events) = Room::connect(livekit_url, livekit_token, room_options)
        .await
        .map_err(|e| format!("Failed to connect to LiveKit: {e:?}"))?;
    keep_key_index_pinned(room.e2ee_manager().clone(), events, e2ee_key_index);
    Ok(room)
}

/// Point every cryptor at the slot the room is actually reading, every time
/// one is made.
///
/// The Rust SDK creates a sender's frame cryptor and never sets its key index,
/// so it encrypts into libwebrtc's default slot 0 — while every Rift client
/// looks this identity up at `keyVersion % 16`. The share then publishes
/// happily and decrypts for nobody: the sharer sees "sharing", the room sees a
/// black tile or silence, and nothing anywhere reports an error.
///
/// Not once after publishing, which is what this used to be: a reconnect
/// republishes every track with a fresh cryptor back on slot 0, so a share that
/// survived the server restarting went on to scramble for everyone. The SDK
/// makes the cryptor before it announces the publish, so the event is late
/// enough. The task ends when the room closes and its event channel with it.
fn keep_key_index_pinned(
    e2ee: E2eeManager,
    mut events: tokio::sync::mpsc::UnboundedReceiver<RoomEvent>,
    e2ee_key_index: i32,
) {
    tokio::spawn(async move {
        while let Some(event) = events.recv().await {
            if matches!(
                event,
                RoomEvent::LocalTrackPublished { .. } | RoomEvent::Reconnected
            ) {
                for (_, cryptor) in e2ee.frame_cryptors() {
                    cryptor.set_key_index(e2ee_key_index);
                }
            }
        }
    });
}
