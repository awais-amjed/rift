//! The watching bridge: a share received by Rust and drawn by the runner
//! (`crate::watching`). Every function exists on every platform, since the
//! bindings are generated once; off the desktop each one answers that there is
//! nothing here, and the app watches through the call's own connection.
#[cfg(desktop)]
use crate::watching::{frames, session, sound};

use crate::frb_generated::StreamSink;
use std::sync::Mutex;

/// The call's room as a watch connection joins it: the address, a token the
/// server minted for `<user>~<device>_watch`, and the call's key and its slot.
pub struct WatchRoom {
    pub livekit_url: String,
    pub livekit_token: String,
    pub e2ee_key: Vec<u8>,
    pub e2ee_key_index: i32,
}

/// Where the runner reads a watched picture: the addresses of
/// `rift_watch_frame_lock` and `rift_watch_frame_unlock`, for Dart to pass on.
pub struct WatchFrameEntry {
    pub lock: usize,
    pub unlock: usize,
}

/// What the watch connection tells the app. One struct and a kind rather
/// than an enum with fields, which the bindings would need `freezed` for.
pub struct WatchEvent {
    pub kind: WatchEventKind,
    /// The share it is about; empty for [`WatchEventKind::Lost`].
    pub share_identity: String,
    pub width: u32,
    pub height: u32,
    /// Why the connection was lost; empty otherwise.
    pub reason: String,
}

pub enum WatchEventKind {
    /// A watched share's picture arrived for the first time, or changed size
    /// (`width` × `height`). The texture carries no shape of its own, so the
    /// app lays the picture out from this.
    PictureSize,
    /// The watch connection is gone for good, or cannot show a share (the
    /// GPU could not decode it): the app watches through the call's
    /// connection again.
    Lost,
}

/// A watched share's receive numbers, as libwebrtc counts them for its
/// picture: cumulative, so the app turns two polls into rates, as it does with
/// the call's own stats.
pub struct WatchStats {
    /// When libwebrtc took them, in microseconds, as flutter_webrtc's are.
    pub timestamp_us: i64,
    pub width: u32,
    pub height: u32,
    pub frames_decoded: u32,
    pub frames_dropped: u32,
    pub frames_per_second: f64,
    pub bytes_received: u64,
    pub packets_received: u64,
    /// Lost so far; it can fall, as late packets turn up.
    pub packets_lost: i64,
    pub jitter_ms: f64,
    /// "VP9", "H264"; empty when libwebrtc did not say.
    pub codec: String,
    /// The connection's round trip; None before a candidate pair connects.
    pub rtt_ms: Option<f64>,
}

static EVENT_SINK: Mutex<Option<StreamSink<WatchEvent>>> = Mutex::new(None);

/// Subscribe to the watch connection's events, for the app's lifetime.
pub fn watch_event_stream(sink: StreamSink<WatchEvent>) {
    *EVENT_SINK.lock().unwrap_or_else(|e| e.into_inner()) = Some(sink);
}

#[cfg(desktop)]
pub(crate) fn emit_watch_event(event: WatchEvent) {
    if let Some(sink) = EVENT_SINK
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
    {
        let _ = sink.add(event);
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn watch_frame_entry_points() -> WatchFrameEntry {
    #[cfg(desktop)]
    {
        let (lock, unlock) = frames::entry_points();
        WatchFrameEntry { lock, unlock }
    }
    #[cfg(not(desktop))]
    {
        WatchFrameEntry { lock: 0, unlock: 0 }
    }
}

/// Open the watch connection into the call's room, replacing one already
/// open. It receives nothing until a share is watched.
pub async fn start_watching(room: WatchRoom) -> Result<(), String> {
    #[cfg(desktop)]
    {
        session::start(room).await
    }
    #[cfg(not(desktop))]
    {
        let _ = room;
        Err("Watching through Rust is desktop-only".to_string())
    }
}

/// Close the watch connection. Succeeds when none was open.
pub async fn stop_watching() -> Result<(), String> {
    #[cfg(desktop)]
    {
        session::stop().await;
    }
    Ok(())
}

/// Receive the share [share_identity] publishes, its picture going to the
/// runner's [texture], which [mark_frame] (the runner's address) marks as
/// each picture arrives, and its sound played where [watch_plays_sound], at
/// what [set_watch_volume] last said (nothing until it does). Watching it
/// already, the texture is replaced and the volume kept.
///
/// [takes_gpu_pictures]: the runner can draw a picture decoded on the GPU
/// into the texture (it imports DMA-BUFs). Where pictures are decoded on the
/// GPU and it cannot, this refuses, and the app watches the call's way.
pub async fn watch_share(
    share_identity: String,
    texture: u64,
    mark_frame: usize,
    takes_gpu_pictures: bool,
) -> Result<(), String> {
    #[cfg(desktop)]
    {
        session::watch(share_identity, texture, mark_frame, takes_gpu_pictures).await
    }
    #[cfg(not(desktop))]
    {
        let _ = (share_identity, texture, mark_frame, takes_gpu_pictures);
        Err("Watching through Rust is desktop-only".to_string())
    }
}

/// Stop receiving [share_identity]. Once this returns, its texture is not
/// marked again, so the runner may let it go.
pub async fn unwatch_share(share_identity: String) -> Result<(), String> {
    #[cfg(desktop)]
    {
        session::unwatch(&share_identity).await;
    }
    #[cfg(not(desktop))]
    {
        let _ = share_identity;
    }
    Ok(())
}

/// [share_identity]'s receive numbers, or None while its picture is not
/// arriving (not watched, not yet subscribed).
pub async fn watch_share_stats(share_identity: String) -> Option<WatchStats> {
    #[cfg(desktop)]
    {
        session::stats(&share_identity).await
    }
    #[cfg(not(desktop))]
    {
        let _ = share_identity;
        None
    }
}

/// Add a key version the call moved to: a share started before the rotation
/// stays sealed under the old one, a share started after it under the new.
pub async fn set_watch_key(e2ee_key: Vec<u8>, e2ee_key_index: i32) -> Result<(), String> {
    #[cfg(desktop)]
    {
        session::add_key(e2ee_key, e2ee_key_index).await
    }
    #[cfg(not(desktop))]
    {
        let _ = (e2ee_key, e2ee_key_index);
        Ok(())
    }
}

/// Turn every watched picture off while nobody can see Rift, and on again,
/// without unwatching: the share stays watched and its sound plays on.
pub async fn set_watch_pictures_on(pictures_on: bool) -> Result<(), String> {
    #[cfg(desktop)]
    {
        session::set_pictures_on(pictures_on).await;
    }
    #[cfg(not(desktop))]
    {
        let _ = pictures_on;
    }
    Ok(())
}

/// Whether this build plays a watched share's sound itself. Where it does,
/// the call's own copy of that sound is held; where not, the call plays it.
#[flutter_rust_bridge::frb(sync)]
pub fn watch_plays_sound() -> bool {
    #[cfg(desktop)]
    {
        sound::PLAYS
    }
    #[cfg(not(desktop))]
    {
        false
    }
}

/// Whether a share sent in H265 would reach the screen on this computer. A
/// viewer says so to whoever shares (`plays`, in `VoiceAttributes`), and a
/// share nobody here could decode steps down to something they can. Asks the
/// driver, so not on the bridge's own thread.
pub async fn watch_plays_h265() -> bool {
    #[cfg(desktop)]
    {
        tokio::task::spawn_blocking(crate::watching::decode::plays_h265)
            .await
            .unwrap_or(false)
    }
    #[cfg(not(desktop))]
    {
        false
    }
}

/// How loud [share_identity]'s sound plays: its own volume times the call's
/// (1 is as sent, up to 8), or 0 while it is muted or this device deafened.
/// Kept for a share whose sound has not arrived yet.
pub async fn set_watch_volume(share_identity: String, volume: f32) -> Result<(), String> {
    #[cfg(desktop)]
    {
        session::set_volume(&share_identity, volume).await;
    }
    #[cfg(not(desktop))]
    {
        let _ = (share_identity, volume);
    }
    Ok(())
}

/// The output a watched share's sound plays on, as WebRTC lists it (None for
/// the system default). Sounds already playing move to it.
#[flutter_rust_bridge::frb(sync)]
pub fn set_watch_output(device_id: Option<String>) {
    #[cfg(desktop)]
    {
        sound::set_output(device_id);
    }
    #[cfg(not(desktop))]
    {
        let _ = device_id;
    }
}
