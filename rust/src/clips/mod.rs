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
#[cfg(target_os = "linux")]
mod sound_linux;

#[cfg(windows)]
mod media_engine;
#[cfg(windows)]
mod poster_windows;
#[cfg(windows)]
mod pulled_stream;
#[cfg(windows)]
mod sound_windows;
#[cfg(windows)]
mod windows;
#[cfg(windows)]
use windows::Clip;

#[cfg(not(any(target_os = "linux", windows)))]
mod elsewhere;
#[cfg(not(any(target_os = "linux", windows)))]
use elsewhere::Clip;

/// A sound decoded whole: 16-bit samples, interleaved.
pub(crate) struct Pcm {
    pub(crate) samples: Vec<i16>,
    pub(crate) channels: u16,
    pub(crate) rate: u32,
}

/// [bytes]' sound, decoded by the system as a chat video's is, at most
/// [max_ms] of it: a soundboard clip, for the cue player to play on the
/// call's device. Fails where the system has no decoder for it.
#[cfg_attr(not(any(target_os = "linux", windows)), allow(dead_code))]
pub(crate) fn decode_sound(bytes: Vec<u8>, max_ms: u32) -> Result<Pcm, String> {
    #[cfg(target_os = "linux")]
    {
        sound_linux::decode(Source::memory(bytes), max_ms)
    }
    #[cfg(windows)]
    {
        sound_windows::decode(Source::memory(bytes), max_ms)
    }
    #[cfg(not(any(target_os = "linux", windows)))]
    {
        let _ = (bytes, max_ms);
        Err("No sound decoder here".to_string())
    }
}

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

/// [source]'s first picture, its longer side at most [longest], as a JPEG:
/// what a video's card shows before it plays. The app's answers for [name]
/// go to [source] meanwhile, as a clip's do for its texture; a poster reads
/// only as far as the file's index and first picture.
pub(crate) fn poster(source: Arc<Source>, name: u64, longest: u32) -> Result<Vec<u8>, String> {
    source::register(name, source.clone());
    #[cfg(target_os = "linux")]
    let made = poster_linux::poster(source, longest);
    #[cfg(windows)]
    let made = poster_windows::poster(source, longest);
    #[cfg(not(any(target_os = "linux", windows)))]
    let made = {
        let _ = (source, longest);
        Err("No poster here yet".to_string())
    };
    source::unregister(name);
    made
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
