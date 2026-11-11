//! A video from the chat, played from memory into one of the runner's
//! textures, the same kind a watched share is drawn into (`crate::watching`).
//!
//! An attachment is decrypted message content and never goes to disk, so the
//! player reads it from memory: from the app, a block at a time as it plays
//! ([`source`]), since a big one is fetched as it is watched. Each
//! platform's own player decodes it, with the system's decoders: Rift ships
//! none for a chat video (the owner's rule on H264, `CALLS.md`). On Linux
//! that is GStreamer ([`linux`]), on Windows the Media Engine ([`windows`]);
//! elsewhere there is none yet ([`available`] false), and the card offers
//! the file to save.
//!
//! A clip is known by its texture: the app makes one per open clip and hands
//! it here, and every call after names it.
use crate::api::clips::{ClipEvent, ClipEventKind};
use crate::watching::frames;
use source::Source;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

pub(crate) mod source;

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
use linux::Clip;
#[cfg(target_os = "linux")]
mod poster_linux;

#[cfg(windows)]
mod media_engine;
#[cfg(windows)]
mod poster_windows;
#[cfg(windows)]
mod pulled_stream;
#[cfg(windows)]
mod windows;
#[cfg(windows)]
use windows::Clip;

#[cfg(not(any(target_os = "linux", windows)))]
mod elsewhere;
#[cfg(not(any(target_os = "linux", windows)))]
use elsewhere::Clip;

/// Whether this computer plays a chat video here: on Windows, one without
/// Media Foundation (an N edition) does not.
pub(crate) fn available() -> bool {
    #[cfg(target_os = "linux")]
    {
        true
    }
    #[cfg(windows)]
    {
        media_engine::usable()
    }
    #[cfg(not(any(target_os = "linux", windows)))]
    {
        false
    }
}

static CLIPS: Mutex<Option<HashMap<u64, Clip>>> = Mutex::new(None);

fn with_clips<R>(f: impl FnOnce(&mut HashMap<u64, Clip>) -> R) -> R {
    let mut guard = CLIPS.lock().unwrap_or_else(|e| e.into_inner());
    f(guard.get_or_insert_with(HashMap::new))
}

/// Opens [source] into [texture], paused on its first picture, its sound
/// to play on [output] (the system's default when none). The app's answers
/// for [texture] go to [source] from now on.
pub(crate) fn open(
    source: Arc<Source>,
    texture: u64,
    mark: frames::MarkFn,
    output: Option<String>,
) -> Result<(), String> {
    close(texture);
    source::register(texture, source.clone());
    frames::open(texture, mark);
    match Clip::open(source, texture, output) {
        Ok(clip) => {
            with_clips(|clips| clips.insert(texture, clip));
            Ok(())
        }
        Err(e) => {
            source::unregister(texture);
            frames::close(texture);
            Err(e)
        }
    }
}

/// Runs [f] on [texture]'s clip; an error when there is none.
pub(crate) fn with<R>(texture: u64, f: impl FnOnce(&Clip) -> R) -> Result<R, String> {
    with_clips(|clips| clips.get(&texture).map(f))
        .ok_or_else(|| "That video is not open".to_string())
}

/// Stops [texture]'s clip and lets its bytes go. Once this returns its
/// texture is not marked again, so the runner may let it go.
pub(crate) fn close(texture: u64) {
    // Its reads woken first: stopping waits for the player's threads, which
    // may be waiting on the app for bytes, or delivering a picture. Then out
    // of the table, and dropped outside its lock.
    source::close(texture);
    let clip = with_clips(|clips| clips.remove(&texture));
    drop(clip);
    source::unregister(texture);
    frames::close(texture);
}

/// [bytes]' first picture, its longer side at most [longest], as a JPEG:
/// what a video's card shows before it plays.
pub(crate) fn poster(bytes: Vec<u8>, longest: u32) -> Result<Vec<u8>, String> {
    #[cfg(target_os = "linux")]
    {
        poster_linux::poster(bytes, longest)
    }
    #[cfg(windows)]
    {
        poster_windows::poster(bytes, longest)
    }
    #[cfg(not(any(target_os = "linux", windows)))]
    {
        let _ = (bytes, longest);
        Err("No poster here yet".to_string())
    }
}

/// What a player tells the app about [texture]'s clip.
#[cfg_attr(not(any(target_os = "linux", windows)), allow(dead_code))]
fn emit(texture: u64, kind: ClipEventKind, width: u32, height: u32, reason: String) {
    crate::api::clips::emit_clip_event(ClipEvent {
        texture,
        kind,
        width,
        height,
        reason,
    });
}
