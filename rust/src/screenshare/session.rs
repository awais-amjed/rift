//! One screen share at a time: bringing it up, and taking it down again.
use super::capture::{self, Capture, CaptureRequest, Feed, Progress, Started, VideoSlot};
#[cfg(gpu_encoder)]
use super::encoder::{self, EncoderSettings, GpuCodec};
#[cfg(gpu_encoder)]
use super::gpu_feed::GpuFeed;
#[cfg(gpu_encoder)]
use super::resolution::fit_within;
use super::resolution::{target_size, Size};
use super::track::{publish_video_track, TrackSettings};
use crate::api::screenshare::types::{self, ScreenShareConfig, ShareQuality, ShareRoom};
#[cfg(gpu_encoder)]
use crate::api::screenshare::types::{ScreenshareEvent, VideoCodec};
use crate::sharing::audio::{self, AudioCapture, AudioCaptureHandle, AudioSelection};
use crate::sharing::room;
use livekit::prelude::*;
use livekit::webrtc::desktop_capturer::DesktopCaptureSourceType;
use livekit::webrtc::prelude::VideoResolution;
use livekit::webrtc::video_source::native::NativeVideoSource;
use std::collections::HashMap;
use std::sync::{Arc, Weak};
use std::time::Duration;
use tokio::sync::Mutex;
use tokio::task::JoinHandle;

/// How long the selected source gets to deliver its first frame, or to say
/// it is waiting for a minimised window. A Wayland portal the user dismissed
/// never does either.
const FIRST_FRAME_TIMEOUT: Duration = Duration::from_secs(10);

/// How long a share still reconnecting on its own is given to finish before
/// it is moved instead — see [`move_to`].
const OWN_RECONNECT_WAIT: Duration = Duration::from_secs(5);

/// The participant attribute a share sets while its window is minimised, which
/// viewers read to say the picture is paused (`VoiceAttributes.sharePausedKey`).
const PAUSED_ATTRIBUTE: &str = "paused";

/// The participant attributes saying what size and rate the share is sending
/// at, which viewers show instead of the rate they measure
/// (`VoiceAttributes.sentPictureOf`). A measured rate drops whenever the
/// screen stands still, so it says less about the share than the setting.
const SIZE_ATTRIBUTE: &str = "size";
const FPS_ATTRIBUTE: &str = "fps";

/// Where LiveKit starts WebRTC's estimate for a new track
/// (`x-google-start-bitrate`). A new GPU encoder starts there too: one that
/// started at the share's cap made frames WebRTC judged to overshoot, and
/// dropped, before its first rate request had even arrived.
#[cfg(gpu_encoder)]
const START_BITRATE_BPS: u32 = 1_000_000;

/// How often, and how many times, a Linux H264 share's encoder is looked at
/// before it is taken to be the GPU's: long enough for the first frames to
/// have gone out, which is when WebRTC names it.
#[cfg(target_os = "linux")]
const H264_CHECK_EVERY: Duration = Duration::from_secs(2);
#[cfg(target_os = "linux")]
const H264_CHECKS: u32 = 5;

/// A screen share's sound keeps the plain name it has always had — nothing
/// reads it, because the picture says what this is.
const AUDIO_TRACK_NAME: &str = "screen_share_audio";

/// The share's own participant, which a move to another room replaces. Held
/// where the capture thread's pause announcements and the picture's publishes
/// both read it, so neither goes on talking to the room that was left.
type SharedParticipant = Arc<std::sync::Mutex<LocalParticipant>>;

struct Session {
    room: Room,
    /// The LiveKit the room is on, so a move to the same one can tell whether
    /// the share is already there.
    livekit_url: String,
    capture: Capture,
    video: Arc<Video>,
    audio: Option<AudioCaptureHandle>,
    /// Whose sound to capture if it is turned on during the share.
    audio_selection: AudioSelection,
    participant: SharedParticipant,
    /// Publishes the picture when its first frame arrives, for a share that
    /// started on a minimised window and is waiting for it to be opened.
    publisher: Option<JoinHandle<()>>,
}

// An async mutex, held for the whole of a start or a stop. A second start
// waits for the first to finish and then finds it "already sharing"; a stop
// during a start waits for the start and then stops it, rather than finding
// nothing and leaving a room connected that no one can reach any more.
static SESSION: Mutex<Option<Session>> = Mutex::const_new(None);

pub(crate) async fn start(config: ScreenShareConfig) -> Result<String, String> {
    types::check(&config)?;
    let mut slot = SESSION.lock().await;
    if slot.is_some() {
        return Err("Already sharing screen".to_string());
    }
    log::info!(
        "screenshare: starting {}p{} at {} Mbps, {:?}, {}, audio {}",
        config.resolution,
        config.fps,
        config.bitrate,
        config.codec,
        if config.capture_full_screen {
            "screen"
        } else {
            "window"
        },
        config.share_audio,
    );

    let room = room::connect(
        &config.livekit_url,
        &config.livekit_token,
        &config.e2ee_key,
        config.e2ee_key_index,
    )
    .await?;
    let room_name = room.name().to_string();
    let room_sid = room.sid().await.to_string();
    log::info!("screenshare: connected to room {room_name} ({room_sid})");

    let participant: SharedParticipant = Arc::new(std::sync::Mutex::new(room.local_participant()));
    let (capture, video, audio, publisher) = match bring_up(&room, &participant, &config).await {
        Ok(parts) => parts,
        Err(reason) => {
            // Leave nothing behind: a room left open here is a ghost
            // participant the app has no handle to.
            if let Err(e) = room.close().await {
                log::warn!("screenshare: closing after a failed start: {e:?}");
            }
            return Err(reason);
        }
    };

    *slot = Some(Session {
        room,
        livekit_url: config.livekit_url.clone(),
        capture,
        video,
        audio,
        audio_selection: AudioSelection::from(&config),
        participant,
        publisher,
    });
    log::info!("screenshare: started");
    Ok(format!("Connected to room: {room_name} ({room_sid})"))
}

pub(crate) async fn stop() -> Result<String, String> {
    let mut slot = SESSION.lock().await;
    let Some(Session {
        room,
        capture,
        audio,
        publisher,
        ..
    }) = slot.take()
    else {
        log::info!("screenshare: stop with nothing running");
        return Ok("No active session".to_string());
    };
    if let Some(publisher) = publisher {
        publisher.abort();
    }

    // Room teardown and the blocking thread joins run at the same time. The
    // capturer's drop (inside the capture join) releases the WGC session,
    // which is what unfreezes the shared window on Windows; closing the room
    // concurrently means viewers see the stream end without also waiting for
    // that, and the window unblocks without waiting for the network.
    let (room_result, _) = tokio::join!(
        room.close(),
        tokio::task::spawn_blocking(move || {
            capture.stop();
            if let Some(audio) = audio {
                audio.terminate();
            }
        }),
    );
    if let Err(e) = room_result {
        log::warn!("screenshare: disconnect reported {e:?}");
    }
    log::info!("screenshare: stopped");
    Ok("Stopped successfully".to_string())
}

/// Takes the running share into the room `to` names, keeping its capture.
///
/// For a call that reconnected — a region change, or a rejoin after the
/// connection gave out. The share's own connection is still in the room the
/// call left, where nobody is watching any more. Starting the share again
/// would open the capture again, and on Wayland that is the portal asking the
/// user to pick their screen a second time; so only the connection is
/// replaced, and the picture and its sound are published again on the new one.
///
/// A share whose call came back on the same LiveKit may have reconnected by
/// itself, into the very room the call is now in. It is left there: a second
/// connection under the same identity would replace it, and viewers would see
/// the stream end and have to start watching again.
///
/// Otherwise the new room is joined before the old one is closed, so a share
/// that cannot get in keeps the one it has.
pub(crate) async fn move_to(to: ShareRoom) -> Result<(), String> {
    types::check_room(&to)?;
    let mut slot = SESSION.lock().await;
    let Some(session) = slot.as_mut() else {
        return Err("Not sharing".to_string());
    };
    if session.livekit_url == to.livekit_url && reconnected_by_itself(&session.room).await {
        log::info!("screenshare: already back in the call's room");
        return Ok(());
    }
    let room = room::connect(
        &to.livekit_url,
        &to.livekit_token,
        &to.e2ee_key,
        to.e2ee_key_index,
    )
    .await?;
    log::info!(
        "screenshare: moving to room {} ({})",
        room.name(),
        room.sid().await
    );

    let old = std::mem::replace(&mut session.room, room);
    session.livekit_url = to.livekit_url;
    *session.participant.lock().unwrap() = session.room.local_participant();
    let audio = session.audio.take();
    let had_audio = audio.is_some();
    let (closed, _) = tokio::join!(
        old.close(),
        tokio::task::spawn_blocking(move || {
            if let Some(audio) = audio {
                audio.terminate();
            }
        }),
    );
    if let Err(e) = closed {
        log::warn!("screenshare: leaving the old room reported {e:?}");
    }

    if let Err(reason) = session.video.move_to_room().await {
        // Nothing is being sent anywhere: end it, the way a closed window
        // does.
        crate::api::screenshare::emit_screenshare_event(
            crate::api::screenshare::types::ScreenshareEvent::SourceClosed,
        );
        return Err(reason);
    }
    if had_audio {
        session.audio = audio::start(
            &session.room,
            AudioCapture {
                selection: session.audio_selection,
                track_name: AUDIO_TRACK_NAME.to_string(),
                on_ended: None,
            },
        )
        .await;
    }
    log::info!("screenshare: moved");
    Ok(())
}

/// Whether `room` is connected, giving one that is still reconnecting a few
/// seconds to get there.
async fn reconnected_by_itself(room: &Room) -> bool {
    let deadline = tokio::time::Instant::now() + OWN_RECONNECT_WAIT;
    loop {
        match room.connection_state() {
            ConnectionState::Connected => return true,
            ConnectionState::Disconnected => return false,
            ConnectionState::Reconnecting if tokio::time::Instant::now() >= deadline => {
                return false
            }
            ConnectionState::Reconnecting => tokio::time::sleep(Duration::from_millis(100)).await,
        }
    }
}

/// Applies what [`ShareQuality`] asks for to the running share, and says what
/// is now in effect — which is sound off if it was asked for and could not be
/// had, so the caller shows the truth rather than its request.
pub(crate) async fn update(quality: ShareQuality) -> Result<ShareQuality, String> {
    types::check_quality(&quality)?;
    let mut slot = SESSION.lock().await;
    let Some(session) = slot.as_mut() else {
        return Err("Not sharing".to_string());
    };
    log::info!(
        "screenshare: changing to {}p{} at {} Mbps, audio {}",
        quality.resolution,
        quality.fps,
        quality.bitrate,
        quality.share_audio
    );

    session.capture.set_fps(quality.fps);
    if session
        .video
        .set_picture(quality.resolution, quality.fps, quality.bitrate)
    {
        if let Err(reason) = session.video.change_picture().await {
            // The old picture is already gone, so the share has nothing to
            // show: end it, the way a closed window does.
            crate::api::screenshare::emit_screenshare_event(
                crate::api::screenshare::types::ScreenshareEvent::SourceClosed,
            );
            return Err(reason);
        }
    }

    match (quality.share_audio, session.audio.take()) {
        (true, None) => {
            session.audio = audio::start(
                &session.room,
                AudioCapture {
                    selection: session.audio_selection,
                    track_name: AUDIO_TRACK_NAME.to_string(),
                    on_ended: None,
                },
            )
            .await;
        }
        (false, Some(handle)) => {
            let track = handle.track();
            if let Err(e) = session
                .room
                .local_participant()
                .unpublish_track(&track)
                .await
            {
                log::warn!("screenshare: unpublishing the sound: {e:?}");
            }
            let _ = tokio::task::spawn_blocking(move || handle.terminate()).await;
        }
        (_, unchanged) => session.audio = unchanged,
    }

    Ok(ShareQuality {
        share_audio: session.audio.is_some(),
        ..quality
    })
}

/// The running share's picture as WebRTC reports it: what encoder it went
/// through, how many frames, and what held it back. For the benchmark.
#[cfg(test)]
pub(crate) async fn video_stats() -> Option<Vec<livekit::webrtc::stats::RtcStats>> {
    let slot = SESSION.lock().await;
    let session = slot.as_ref()?;
    let sid = session.video.track.lock().await.clone()?;
    let publication = session
        .room
        .local_participant()
        .get_track_publication(&sid)?;
    match publication.track()? {
        LocalTrack::Video(track) => track.get_stats().await.ok(),
        _ => None,
    }
}

/// The pieces of a running share, as [`bring_up`] leaves them.
type Parts = (
    Capture,
    Arc<Video>,
    Option<AudioCaptureHandle>,
    Option<JoinHandle<()>>,
);

/// Everything after the room exists. On any error the capture thread is
/// already stopped; the caller closes the room.
async fn bring_up(
    room: &Room,
    participant: &SharedParticipant,
    config: &ScreenShareConfig,
) -> Result<Parts, String> {
    let (capture, mut started) = capture::spawn(CaptureRequest {
        source_type: if config.capture_full_screen {
            DesktopCaptureSourceType::Screen
        } else {
            DesktopCaptureSourceType::Window
        },
        selected_index: config.selected_video_source_index,
        fps: config.fps,
        capture_cursor: true,
        on_minimised: Some(announce_paused(participant.clone())),
    });

    let first = match tokio::time::timeout(FIRST_FRAME_TIMEOUT, started.recv()).await {
        Ok(Some(Progress::FirstFrame(size))) => Some(size),
        Ok(Some(Progress::Waiting)) => None,
        Ok(Some(Progress::Failed(reason))) => return Err(stop_capture(capture, reason).await),
        Ok(None) => {
            let reason = "The capture thread stopped before producing a frame".to_string();
            return Err(stop_capture(capture, reason).await);
        }
        Err(_) => {
            let reason = format!(
                "No frames arrived from the selected source in {} seconds",
                FIRST_FRAME_TIMEOUT.as_secs()
            );
            return Err(stop_capture(capture, reason).await);
        }
    };

    let video = Arc::new_cyclic(|me| Video {
        me: me.clone(),
        participant: participant.clone(),
        slot: capture.slot(),
        settings: std::sync::Mutex::new(TrackSettings::from(config)),
        track: Mutex::new(None),
        #[cfg(gpu_encoder)]
        gpu: std::sync::Mutex::new(None),
    });
    // A window still on the taskbar: the share is up — viewers see it, marked
    // paused — and the picture goes out once the user opens the window, which
    // is theirs to do when they are ready. Waiting here instead would hold the
    // session lock, and with it any stop, for as long as that takes.
    let publisher = match first {
        Some(native) => {
            if let Err(reason) = video.publish(native).await {
                return Err(stop_capture(capture, reason).await);
            }
            None
        }
        None => {
            log::info!("screenshare: waiting for the window to be opened");
            Some(tokio::spawn(publish_when_opened(video.clone(), started)))
        }
    };

    // A screen share's sound has no `on_ended`: if the window stops playing,
    // the picture is still worth watching.
    let audio = if config.share_audio {
        audio::start(
            room,
            AudioCapture {
                selection: AudioSelection::from(config),
                track_name: AUDIO_TRACK_NAME.to_string(),
                on_ended: None,
            },
        )
        .await
    } else {
        None
    };
    Ok((capture, video, audio, publisher))
}

/// What publishing the picture needs, none of it borrowed from the start.
struct Video {
    /// For a GPU encoder failing mid-share, which republishes from another
    /// thread and must not keep a stopped share alive to do it.
    #[cfg_attr(not(gpu_encoder), allow(dead_code))]
    me: Weak<Video>,
    participant: SharedParticipant,
    slot: VideoSlot,
    /// Changed by [`update`]; read each time the picture is published.
    settings: std::sync::Mutex<TrackSettings>,
    /// The published track, once there is one. Held for the whole of a
    /// publish, so a change made while a minimised window is opening waits
    /// for the first publish and then redoes it, rather than racing it.
    track: Mutex<Option<TrackSid>>,
    /// The picture's encoder and the source it feeds, while the GPU makes it.
    #[cfg(gpu_encoder)]
    gpu: std::sync::Mutex<Option<GpuPicture>>,
}

/// A published picture the GPU encodes.
#[cfg(gpu_encoder)]
struct GpuPicture {
    source: NativeVideoSource,
    feed: Arc<GpuFeed>,
    /// The rate it was published at, which WebRTC holds the track to.
    published_fps: u32,
    /// The bitrate cap it was published at, in Mbps, which WebRTC's requests
    /// never go above.
    published_bitrate: u32,
}

impl Video {
    /// Who publishes the picture now — see [`SharedParticipant`].
    fn participant(&self) -> LocalParticipant {
        self.participant.lock().unwrap().clone()
    }

    /// Size a video source for the first frame, start feeding it, publish it.
    async fn publish(&self, native: Size) -> Result<(), String> {
        let mut track = self.track.lock().await;
        self.publish_locked(&mut track, native).await
    }

    /// Takes the new height and rate, and says whether either changed.
    fn set_picture(&self, max_height: u32, fps: u32, bitrate: u32) -> bool {
        let mut settings = self.settings.lock().unwrap();
        let changed =
            settings.max_height != max_height || settings.fps != fps || settings.bitrate != bitrate;
        settings.max_height = max_height;
        settings.fps = fps;
        settings.bitrate = bitrate;
        changed
    }

    /// Put a new size or rate into effect.
    async fn change_picture(&self) -> Result<(), String> {
        #[cfg(gpu_encoder)]
        if let Some(changed) = self.reopen_gpu().await {
            return changed;
        }
        self.republish().await
    }

    /// Change a GPU picture on the track it already has: the encoder is
    /// replaced, the track kept. A new track starts WebRTC's estimate over
    /// from LiveKit's 1 Mbps, and against that WebRTC dropped the new
    /// encoder's frames until no picture got through at all (3 runs of 3,
    /// Oct 4 2026); on the old track the new encoder starts where the old one
    /// had got to, and viewers do not even see the picture blink.
    ///
    /// `None` when that does not apply, and the picture is republished: not
    /// on the GPU, not published yet, or faster or richer than WebRTC holds
    /// the track to. A new encoder that will not open hands the share to VP9.
    #[cfg(gpu_encoder)]
    async fn reopen_gpu(&self) -> Option<Result<(), String>> {
        let opened = {
            let track = self.track.lock().await;
            track.as_ref()?;
            let settings = *self.settings.lock().unwrap();
            let (source, old, published_fps, published_bitrate) = {
                let gpu = self.gpu.lock().unwrap();
                let picture = gpu.as_ref()?;
                (
                    picture.source.clone(),
                    picture.feed.clone(),
                    picture.published_fps,
                    picture.published_bitrate,
                )
            };
            if settings.fps > published_fps || settings.bitrate > published_bitrate {
                return None;
            }
            let codec = GpuCodec::for_share(settings.codec)?;
            let native = self.slot.native()?;
            let target = gpu_target(target_size(native, settings.max_height));
            log::info!(
                "screenshare: re-encoding at {}x{}, {} fps, on the same track",
                target.width,
                target.height,
                settings.fps
            );
            // The old encoder closes before the new one opens.
            let start = old.bitrate();
            self.slot.detach();
            *self.gpu.lock().unwrap() = None;
            drop(old);
            let fed = source.clone();
            let encoder = encoder_settings(codec, target, &settings, start);
            let on_failed = self.on_gpu_failed();
            let opened =
                tokio::task::spawn_blocking(move || GpuFeed::open(&fed, encoder, on_failed))
                    .await
                    .map_err(|e| format!("The GPU encoder did not open: {e}"))
                    .and_then(|opened| opened);
            match opened {
                Ok(feed) => {
                    let feed = Arc::new(feed);
                    self.slot.attach(Feed::Gpu(feed.clone()), target);
                    *self.gpu.lock().unwrap() = Some(GpuPicture {
                        source,
                        feed,
                        published_fps,
                        published_bitrate,
                    });
                    announce_picture(&self.participant(), target, settings.fps);
                    Ok(())
                }
                Err(reason) => Err(reason),
            }
        };
        match opened {
            Ok(()) => Some(Ok(())),
            Err(reason) => {
                self.fall_back(&reason);
                Some(self.republish().await)
            }
        }
    }

    /// Publish the picture again at the current settings. A share still
    /// waiting on a minimised window has nothing to redo: it publishes at
    /// these settings when the window opens.
    ///
    /// The track is replaced rather than retuned: its size is fixed when its
    /// source is made, and the SDK has no call to change a sender's encoding.
    /// Viewers stay subscribed — the share's connection is what they watch —
    /// and see the picture blink.
    async fn republish(&self) -> Result<(), String> {
        let mut track = self.track.lock().await;
        let Some(old) = track.take() else {
            return Ok(());
        };
        let native = self
            .slot
            .native()
            .ok_or("No frame has been captured to size the picture by")?;
        self.slot.detach();
        if let Err(e) = self.participant().unpublish_track(&old).await {
            log::warn!("screenshare: unpublishing the old picture: {e:?}");
        }
        self.publish_locked(&mut track, native).await
    }

    /// Publish the picture again on the participant a move just put in
    /// place. Its track went with the room it was in, so there is nothing to
    /// unpublish; a share still waiting on a minimised window publishes on the
    /// new participant when the window opens.
    async fn move_to_room(&self) -> Result<(), String> {
        let mut track = self.track.lock().await;
        if track.take().is_none() {
            return Ok(());
        }
        let native = self
            .slot
            .native()
            .ok_or("No frame has been captured to size the picture by")?;
        self.slot.detach();
        #[cfg(gpu_encoder)]
        {
            *self.gpu.lock().unwrap() = None;
        }
        self.publish_locked(&mut track, native).await
    }

    async fn publish_locked(
        &self,
        track: &mut Option<TrackSid>,
        native: Size,
    ) -> Result<(), String> {
        #[allow(unused_mut)]
        let mut settings = *self.settings.lock().unwrap();
        let target = target_size(native, settings.max_height);
        log::info!(
            "screenshare: capturing {}x{}, publishing {}x{}",
            native.width,
            native.height,
            target.width,
            target.height
        );

        // H264 comes from the GPU or not at all (ARCHITECTURE.md, "Encoding a
        // share on the GPU"): from Rift's own encoder where there is one, and
        // as VP9 if it will not open. On Linux without NVENC it is LiveKit's
        // VAAPI encoder, checked once it has made frames.
        #[cfg(gpu_encoder)]
        if let Some(codec) =
            GpuCodec::for_share(settings.codec).filter(|&codec| encoder::encodes_itself(codec))
        {
            let target = gpu_target(target);
            match self.publish_from_gpu(target, codec, &settings).await {
                Ok(sid) => {
                    *track = Some(sid);
                    announce_picture(&self.participant(), target, settings.fps);
                    return Ok(());
                }
                Err(reason) => settings = self.fall_back(&reason),
            }
        }

        let source = NativeVideoSource::new(
            VideoResolution {
                width: target.width,
                height: target.height,
            },
            false,
        );
        #[cfg(gpu_encoder)]
        {
            *self.gpu.lock().unwrap() = None;
        }
        self.slot.attach(Feed::Raw(source.clone()), target);
        let sid = publish_video_track(&self.participant(), source, &settings, false).await?;
        #[cfg(target_os = "linux")]
        if settings.codec == VideoCodec::H264 {
            self.check_h264_encoder(sid.clone());
        }
        *track = Some(sid);
        announce_picture(&self.participant(), target, settings.fps);
        Ok(())
    }

    /// Linux without NVENC: H264 comes from LiveKit's VAAPI encoder, and is
    /// offered only where LiveKit lists one. A listed one can still fail to
    /// open, and LiveKit then quietly makes H264 with OpenH264 on the CPU,
    /// which Rift never does (`ARCHITECTURE.md`, "Encoding a share on the
    /// GPU"). So once the first frames are out, the encoder WebRTC names is
    /// checked, and anything but the GPU's hands the share to VP9.
    #[cfg(target_os = "linux")]
    fn check_h264_encoder(&self, sid: TrackSid) {
        let me = self.me.clone();
        tokio::spawn(async move {
            for _ in 0..H264_CHECKS {
                tokio::time::sleep(H264_CHECK_EVERY).await;
                let Some(video) = me.upgrade() else {
                    return;
                };
                // A newer picture has its own check.
                if video.track.lock().await.as_ref() != Some(&sid) {
                    return;
                }
                let Some(name) = video.encoder_name(&sid).await else {
                    continue;
                };
                if encoder::is_gpu_h264(&name) {
                    log::info!("screenshare: H264 from {name}");
                    return;
                }
                video.fall_back(&format!("H264 came from {name}, not the GPU"));
                if let Err(reason) = video.republish().await {
                    log::warn!("screenshare: {reason}");
                    crate::api::screenshare::emit_screenshare_event(ScreenshareEvent::SourceClosed);
                }
                return;
            }
            log::warn!("screenshare: no encoder named for the H264 picture yet");
        });
    }

    /// The encoder WebRTC says made the picture `sid`, once it has made some.
    #[cfg(target_os = "linux")]
    async fn encoder_name(&self, sid: &TrackSid) -> Option<String> {
        let publication = self.participant().get_track_publication(sid)?;
        let LocalTrack::Video(track) = publication.track()? else {
            return None;
        };
        let stats = track.get_stats().await.ok()?;
        stats.into_iter().find_map(|stat| match stat {
            livekit::webrtc::stats::RtcStats::OutboundRtp(out)
                if out.stream.kind == "video"
                    && !out.outbound.encoder_implementation.is_empty() =>
            {
                Some(out.outbound.encoder_implementation)
            }
            _ => None,
        })
    }

    /// Open a hardware encoder for the picture and publish what it makes.
    #[cfg(gpu_encoder)]
    async fn publish_from_gpu(
        &self,
        target: Size,
        codec: GpuCodec,
        settings: &TrackSettings,
    ) -> Result<TrackSid, String> {
        let source = NativeVideoSource::new_encoded(VideoResolution {
            width: target.width,
            height: target.height,
        });
        let fed = source.clone();
        let encoder = encoder_settings(codec, target, settings, START_BITRATE_BPS);
        let on_failed = self.on_gpu_failed();
        let feed = tokio::task::spawn_blocking(move || GpuFeed::open(&fed, encoder, on_failed))
            .await
            .map_err(|e| format!("The GPU encoder did not open: {e}"))??;
        log::info!("screenshare: encoding on {}", feed.name());
        let feed = Arc::new(feed);
        self.slot.attach(Feed::Gpu(feed.clone()), target);
        let sid = publish_video_track(&self.participant(), source.clone(), settings, true).await?;
        *self.gpu.lock().unwrap() = Some(GpuPicture {
            source,
            feed,
            published_fps: settings.fps,
            published_bitrate: settings.bitrate,
        });
        Ok(sid)
    }

    /// Give up on the GPU for the rest of this share, and say so.
    #[cfg(gpu_encoder)]
    fn fall_back(&self, reason: &str) -> TrackSettings {
        log::warn!("screenshare: {reason}; sharing as VP9 instead");
        let mut settings = self.settings.lock().unwrap();
        settings.codec = VideoCodec::VP9;
        crate::api::screenshare::emit_screenshare_event(ScreenshareEvent::EncoderFellBack);
        *settings
    }

    /// What the processing thread calls when the encoder stops working
    /// mid-share: publish again as VP9, so the picture never stays black.
    #[cfg(gpu_encoder)]
    fn on_gpu_failed(&self) -> Box<dyn Fn() + Send + Sync> {
        let me = self.me.clone();
        let runtime = tokio::runtime::Handle::current();
        Box::new(move || {
            let me = me.clone();
            runtime.spawn(async move {
                let Some(video) = me.upgrade() else {
                    return;
                };
                video.fall_back("The GPU encoder stopped working");
                if let Err(reason) = video.republish().await {
                    log::warn!("screenshare: {reason}");
                    crate::api::screenshare::emit_screenshare_event(ScreenshareEvent::SourceClosed);
                }
            });
        })
    }
}

/// The size the GPU encodes a `target` at: the same, unless it is bigger than
/// a hardware encoder takes, when it is scaled down to fit rather than going
/// to VP9 on the CPU.
#[cfg(gpu_encoder)]
fn gpu_target(target: Size) -> Size {
    let fitted = fit_within(target, encoder::MAX_SIZE);
    if fitted != target {
        log::info!(
            "screenshare: {}x{} is bigger than the GPU encodes; encoding at {}x{}",
            target.width,
            target.height,
            fitted.width,
            fitted.height
        );
    }
    fitted
}

/// What a share's encoder is opened for: `codec` at the target size and the
/// share's rate, held to its cap, starting at `start_bitrate_bps`.
#[cfg(gpu_encoder)]
fn encoder_settings(
    codec: GpuCodec,
    target: Size,
    settings: &TrackSettings,
    start_bitrate_bps: u32,
) -> EncoderSettings {
    EncoderSettings {
        codec,
        width: target.width,
        height: target.height,
        fps: settings.fps,
        max_bitrate_bps: settings.bitrate.saturating_mul(1_000_000),
        start_bitrate_bps,
    }
}

/// Tells the room the size and rate a newly published picture goes out at.
/// Not awaited: the share is up either way, and a viewer without it falls
/// back to what it measures.
fn announce_picture(participant: &LocalParticipant, size: Size, fps: u32) {
    let participant = participant.clone();
    tokio::spawn(async move {
        let attributes = HashMap::from([
            (
                SIZE_ATTRIBUTE.to_string(),
                format!("{}x{}", size.width, size.height),
            ),
            (FPS_ATTRIBUTE.to_string(), fps.to_string()),
        ]);
        if let Err(e) = participant.set_attributes(attributes).await {
            log::warn!("screenshare: telling viewers the picture: {e:?}");
        }
    });
}

/// The rest of a share that started on a minimised window. A stop aborts it;
/// a window closed while waiting has already told Flutter, which stops it.
async fn publish_when_opened(video: Arc<Video>, mut started: Started) {
    while let Some(progress) = started.recv().await {
        match progress {
            Progress::Waiting => {}
            Progress::Failed(reason) => {
                log::info!("screenshare: gave up waiting: {reason}");
                return;
            }
            Progress::FirstFrame(native) => {
                if let Err(reason) = video.publish(native).await {
                    // The share is up with nothing to show and no way to put
                    // it right from here: end it, the way a closed window does.
                    log::warn!("screenshare: {reason}");
                    crate::api::screenshare::emit_screenshare_event(
                        crate::api::screenshare::types::ScreenshareEvent::SourceClosed,
                    );
                }
                return;
            }
        }
    }
}

/// Tells the room, as an attribute of the share's own connection, when the
/// shared window is minimised and when it is back. Called from the capture
/// thread, so the request is handed to the runtime rather than awaited there.
fn announce_paused(participant: SharedParticipant) -> Box<dyn Fn(bool) + Send> {
    let runtime = tokio::runtime::Handle::current();
    Box::new(move |paused| {
        let participant = participant.lock().unwrap().clone();
        runtime.spawn(async move {
            let attributes = HashMap::from([(PAUSED_ATTRIBUTE.to_string(), paused.to_string())]);
            if let Err(e) = participant.set_attributes(attributes).await {
                log::warn!("screenshare: telling viewers paused={paused}: {e:?}");
            }
        });
    })
}

/// Stop a capture off the async runtime, and hand back the reason it is being
/// stopped so the error path reads as one expression.
async fn stop_capture(capture: Capture, reason: String) -> String {
    let _ = tokio::task::spawn_blocking(move || capture.stop()).await;
    reason
}
