//! The chat video bridge: a video attachment played from memory into a
//! runner texture (`crate::clips`). Every function exists on every platform,
//! since the bindings are generated once; where there is no player each one
//! says so, and the app offers the file to save.
#[cfg(desktop)]
use crate::clips;

use crate::frb_generated::StreamSink;
use std::sync::Mutex;

/// What a playing video tells the app. One struct and a kind rather than an
/// enum with fields, which the bindings would need `freezed` for.
pub struct ClipEvent {
    /// The texture the clip draws into, which names it.
    pub texture: u64,
    pub kind: ClipEventKind,
    pub width: u32,
    pub height: u32,
    /// Why it failed, in the player's words; empty otherwise.
    pub reason: String,
}

pub enum ClipEventKind {
    /// The first picture arrived, or its shape changed (`width` × `height`,
    /// as shown).
    PictureSize,
    /// It played to the end.
    Ended,
    /// Nothing on this system decodes what the file holds.
    CannotDecode,
    /// It failed some other way.
    Failed,
}

/// A player asking for its file's bytes: [length] of them from [offset],
/// which the app answers with `clip_answer` (or `clip_refuse`) naming the
/// same [request].
pub struct ClipRead {
    pub texture: u64,
    pub request: u64,
    pub offset: u64,
    pub length: u32,
}

/// Where a clip is, in milliseconds, where the player knows.
pub struct ClipTime {
    pub position_ms: Option<u64>,
    pub duration_ms: Option<u64>,
}

static EVENT_SINK: Mutex<Option<StreamSink<ClipEvent>>> = Mutex::new(None);
static READ_SINK: Mutex<Option<StreamSink<ClipRead>>> = Mutex::new(None);

/// What every clip reports, on one stream for the app's life.
pub fn clip_event_stream(sink: StreamSink<ClipEvent>) {
    *EVENT_SINK.lock().unwrap_or_else(|e| e.into_inner()) = Some(sink);
}

#[cfg(desktop)]
pub(crate) fn emit_clip_event(event: ClipEvent) {
    if let Some(sink) = EVENT_SINK
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
    {
        let _ = sink.add(event);
    }
}

/// What every clip's player asks for, on one stream for the app's life.
pub fn clip_read_stream(sink: StreamSink<ClipRead>) {
    *READ_SINK.lock().unwrap_or_else(|e| e.into_inner()) = Some(sink);
}

#[cfg(desktop)]
pub(crate) fn emit_clip_read(read: ClipRead) {
    if let Some(sink) = READ_SINK
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
    {
        let _ = sink.add(read);
    }
}

/// The bytes [texture]'s player asked for in [request]: fewer than asked
/// where the file ends.
pub fn clip_answer(texture: u64, request: u64, bytes: Vec<u8>) {
    #[cfg(desktop)]
    {
        clips::source::answer(texture, request, Ok(bytes));
    }
    #[cfg(not(desktop))]
    {
        let _ = (texture, request, bytes);
    }
}

/// [texture]'s [request] cannot be answered, for [reason]: the clip fails.
pub fn clip_refuse(texture: u64, request: u64, reason: String) {
    #[cfg(desktop)]
    {
        clips::source::answer(texture, request, Err(reason));
    }
    #[cfg(not(desktop))]
    {
        let _ = (texture, request, reason);
    }
}

/// Whether this build plays a chat video itself.
#[flutter_rust_bridge::frb(sync)]
pub fn clips_available() -> bool {
    #[cfg(desktop)]
    {
        clips::available()
    }
    #[cfg(not(desktop))]
    {
        false
    }
}

/// Opens a video file of [length] bytes into the runner's [texture], which
/// [mark_frame] (the runner's address) marks when a picture waits. Its
/// player reads the file by asking for it (`clip_read_stream`). Paused on
/// its first picture; its sound plays on [output], the system's default when
/// none.
pub async fn clip_open(
    length: u64,
    texture: u64,
    mark_frame: usize,
    output: Option<String>,
) -> Result<(), String> {
    #[cfg(desktop)]
    {
        if mark_frame == 0 {
            return Err("No runner to draw the video".to_string());
        }
        // SAFETY: the runner's address for its mark function, as for a
        // watched share (`watch_share`).
        let mark: crate::watching::frames::MarkFn =
            unsafe { std::mem::transmute::<usize, crate::watching::frames::MarkFn>(mark_frame) };
        let source = clips::source::Source::pulled(
            texture,
            length,
            Box::new(emit_clip_read),
        );
        tokio::task::spawn_blocking(move || clips::open(source, texture, mark, output))
            .await
            .map_err(|e| e.to_string())?
    }
    #[cfg(not(desktop))]
    {
        let _ = (length, texture, mark_frame, output);
        Err("Videos do not play here".to_string())
    }
}

/// [bytes]' first picture, a whole video file's, its longer side at most
/// [longest], as a JPEG: what the video's card shows before it plays.
pub async fn clip_poster(bytes: Vec<u8>, longest: u32) -> Result<Vec<u8>, String> {
    #[cfg(desktop)]
    {
        tokio::task::spawn_blocking(move || clips::poster(bytes, longest))
            .await
            .map_err(|e| e.to_string())?
    }
    #[cfg(not(desktop))]
    {
        let _ = (bytes, longest);
        Err("No poster here".to_string())
    }
}

pub fn clip_play(texture: u64) -> Result<(), String> {
    #[cfg(desktop)]
    {
        clips::with(texture, |c| c.play())?
    }
    #[cfg(not(desktop))]
    {
        let _ = texture;
        Ok(())
    }
}

pub fn clip_pause(texture: u64) -> Result<(), String> {
    #[cfg(desktop)]
    {
        clips::with(texture, |c| c.pause())?
    }
    #[cfg(not(desktop))]
    {
        let _ = texture;
        Ok(())
    }
}

pub fn clip_seek(texture: u64, position_ms: u64) -> Result<(), String> {
    #[cfg(desktop)]
    {
        clips::with(texture, |c| c.seek(position_ms))?
    }
    #[cfg(not(desktop))]
    {
        let _ = (texture, position_ms);
        Ok(())
    }
}

/// 1 as recorded; up to 4.
pub fn clip_set_volume(texture: u64, volume: f64) {
    #[cfg(desktop)]
    {
        let _ = clips::with(texture, |c| c.set_volume(volume));
    }
    #[cfg(not(desktop))]
    {
        let _ = (texture, volume);
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn clip_time(texture: u64) -> ClipTime {
    #[cfg(desktop)]
    {
        let (position_ms, duration_ms) = clips::with(texture, |c| c.time()).unwrap_or((None, None));
        ClipTime {
            position_ms,
            duration_ms,
        }
    }
    #[cfg(not(desktop))]
    {
        let _ = texture;
        ClipTime {
            position_ms: None,
            duration_ms: None,
        }
    }
}

/// Stops [texture]'s clip and lets the file go. Once this returns, the
/// texture is not marked again.
pub async fn clip_close(texture: u64) {
    #[cfg(desktop)]
    {
        let _ = tokio::task::spawn_blocking(move || clips::close(texture)).await;
    }
    #[cfg(not(desktop))]
    {
        let _ = texture;
    }
}
