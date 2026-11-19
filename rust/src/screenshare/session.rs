//! One screen share at a time: bringing it up, and taking it down again.
use super::capture::{self, Capture, CaptureRequest, Feed, Progress, Started, VideoSlot};
#[cfg(gpu_encoder)]
use super::encoder::{self, EncoderSettings, GpuCodec};
use super::first_probe::FirstFrames;
#[cfg(gpu_encoder)]
use super::gpu_feed::GpuFeed;
#[cfg(gpu_encoder)]
use super::resolution::fit_within;
use super::resolution::{target_size, Size};
use super::send_report::{self, SendTotals};
use super::sources;
use super::stops::Stops;
#[cfg(gpu_encoder)]
use super::step_down::StepDown;
use super::track::{publish_video_track, TrackSettings};
use crate::api::screenshare::types::{
    self, ScreenShareConfig, ShareCursor, ShareQuality, ShareRoom, ShareSource, VideoCodec,
};
#[cfg(gpu_encoder)]
use crate::api::screenshare::types::ScreenshareEvent;
use crate::sharing::audio::{self, AudioCapture, AudioCaptureHandle, AudioSelection};
use crate::sharing::room;
use crate::watching::receive_report::{self, Report};
use livekit::prelude::*;
use livekit::webrtc::prelude::VideoResolution;
use livekit::webrtc::video_source::native::NativeVideoSource;
use std::collections::HashMap;
use std::sync::{Arc, Weak};
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::task::JoinHandle;

/// How long the selected source gets to deliver its first frame, or to say
/// it is waiting for a minimised window. A Wayland portal the user dismissed
/// never does either, under libwebrtc's capturer. On Rift's own stream the
/// time starts once the picker has its answer.
pub(super) const FIRST_FRAME_TIMEOUT: Duration = Duration::from_secs(10);

/// How long the desktop's picker is left up on Rift's own stream, as long
/// as Dart leaves its window picker (`WindowSharePortal`).
const PICKER_TIMEOUT: Duration = Duration::from_secs(600);

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

/// Where LiveKit starts WebRTC's estimate for a new track at most
/// (`x-google-start-bitrate`), for every codec, and lower after a slow
/// connection setup. Rift's fork caps a share's as a camera's (its `RIFT.md`):
/// one opened near its cap probed above it, and a slower upload lost its first
/// seconds. A new GPU encoder starts here too: one that started at the share's
/// cap made frames WebRTC judged to overshoot, and
/// dropped, before its first rate request had even arrived.
#[cfg(gpu_encoder)]
const START_BITRATE_BPS: u32 = 1_000_000;

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
    /// None only between a Windows switch stopping the old capture and the
    /// new one starting ([`switch`]).
    capture: Option<Capture>,
    /// Whether the cursor is drawn, for a capture a switch starts.
    cursor: ShareCursor,
    video: Arc<Video>,
    audio: Option<AudioCaptureHandle>,
    /// Whose sound to capture if it is turned on during the share.
    audio_selection: AudioSelection,
    participant: SharedParticipant,
    /// Publishes the picture when its first frame arrives, for a share that
    /// started on a minimised window and is waiting for it to be opened.
    publisher: Option<JoinHandle<()>>,
    /// Says what WebRTC sent every few seconds ([`report_sending`]).
    reporter: JoinHandle<()>,
    /// Asks for a probe as a connection's pictures begin to flow
    /// ([`probe_first_frames`]).
    prober: JoinHandle<()>,
    /// Tells the step-down when nobody watches ([`follow_pause`]).
    #[cfg(gpu_encoder)]
    pause_follower: JoinHandle<()>,
}

// An async mutex, held for the whole of a start or a stop. A second start
// waits for the first to finish and then finds it "already sharing"; a stop
// during a start waits for the start and then stops it, rather than finding
// nothing and leaving a room connected that no one can reach any more.
static SESSION: Mutex<Option<Session>> = Mutex::const_new(None);

// Stops on their way, which a switch waiting on its new source hears: it
// holds the session meanwhile, and under Wayland that wait is on a person.
static STOPS: Stops = Stops::new();

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
        capture: Some(capture),
        cursor: config.cursor,
        video,
        audio,
        audio_selection: AudioSelection::from(&config),
        participant,
        publisher,
        reporter: tokio::spawn(report_sending()),
        prober: tokio::spawn(probe_first_frames()),
        #[cfg(gpu_encoder)]
        pause_follower: tokio::spawn(follow_pause()),
    });
    sources::set_sharing(sources::chosen(
        config.capture_full_screen,
        config.selected_video_source_index,
    ));
    log::info!("screenshare: started");
    Ok(format!("Connected to room: {room_name} ({room_sid})"))
}

pub(crate) async fn stop() -> Result<String, String> {
    let _stopping = STOPS.begin();
    let mut slot = SESSION.lock().await;
    let Some(Session {
        room,
        capture,
        audio,
        publisher,
        reporter,
        prober,
        #[cfg(gpu_encoder)]
        pause_follower,
        ..
    }) = slot.take()
    else {
        log::info!("screenshare: stop with nothing running");
        return Ok("No active session".to_string());
    };
    if let Some(publisher) = publisher {
        publisher.abort();
    }
    reporter.abort();
    prober.abort();
    #[cfg(gpu_encoder)]
    pause_follower.abort();

    // Room teardown and the blocking thread joins run at the same time. The
    // capturer's drop (inside the capture join) releases the WGC session,
    // which is what unfreezes the shared window on Windows; closing the room
    // concurrently means viewers see the stream end without also waiting for
    // that, and the window unblocks without waiting for the network.
    let (room_result, _) = tokio::join!(
        room.close(),
        tokio::task::spawn_blocking(move || {
            if let Some(capture) = capture {
                capture.stop();
            }
            if let Some(audio) = audio {
                audio.terminate();
            }
        }),
    );
    sources::set_sharing(None);
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
                selection: session.audio_selection.clone(),
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
        "screenshare: changing to {}p{} at {} Mbps in {:?}, audio {}",
        quality.resolution,
        quality.fps,
        quality.bitrate,
        quality.codec,
        quality.share_audio
    );

    if let Some(capture) = &session.capture {
        capture.set_fps(quality.fps);
    }
    let new_codec = session.video.set_codec(quality.codec);
    let new_picture = session
        .video
        .set_picture(quality.resolution, quality.fps, quality.bitrate);
    if new_codec || new_picture {
        // A track's codec is settled when it is published, so another codec
        // is another track; a size or rate alone may keep the one it has.
        let changed = if new_codec {
            session.video.republish().await
        } else {
            session.video.change_picture().await
        };
        if let Err(reason) = changed {
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
                    selection: session.audio_selection.clone(),
                    track_name: AUDIO_TRACK_NAME.to_string(),
                    on_ended: None,
                },
            )
            .await;
        }
        (false, Some(handle)) => end_sound(&session.room, handle).await,
        (_, unchanged) => session.audio = unchanged,
    }

    Ok(ShareQuality {
        codec: session.video.codec(),
        share_audio: session.audio.is_some(),
        ..quality
    })
}

/// Whether a switch stops the old capture before starting the new one.
///
/// On Windows it has to: a share holds one GPU device, which its encoder opens
/// on (`capture_wgc::SHARE_DEVICE`), and Windows 10 duplicates a screen only
/// once a process. The pick was made in Rift's own list there, so the gap is
/// only the new capture's start. Elsewhere the new capture starts beside the
/// old: under Wayland the desktop's picker comes up for it, and viewers keep
/// the old picture while it is open, or for good if it is cancelled.
const STOPS_OLD_FIRST: bool = cfg!(target_os = "windows");

/// Switch the running share to another screen or window, on the same
/// connection, so viewers keep watching. The picture keeps its track where
/// its size allows, and is published again where it does not. Returns
/// whether its sound goes on: a window on Windows brings its own app's.
pub(crate) async fn switch(source: ShareSource) -> Result<bool, String> {
    let mut slot = SESSION.lock().await;
    let Some(session) = slot.as_mut() else {
        return Err("Not sharing".to_string());
    };
    let chosen = sources::chosen(
        source.capture_full_screen,
        source.selected_video_source_index,
    );
    if sources::same_source(chosen, sources::sharing()) {
        log::info!("screenshare: already sharing that");
        return Ok(session.audio.is_some());
    }
    log::info!(
        "screenshare: switching to a {}",
        if source.capture_full_screen {
            "screen"
        } else {
            "window"
        }
    );
    // A share still waiting on a minimised window waits no longer.
    if let Some(publisher) = session.publisher.take() {
        publisher.abort();
    }
    let settings = *session.video.settings.lock().unwrap();
    let request = capture_request(
        &source,
        session.video.codec(),
        settings.fps,
        session.cursor,
        settings.gpu_capture,
        &session.participant,
    );

    let mut held = None;
    if STOPS_OLD_FIRST {
        held = session.video.slot().take();
        if let Some(old) = session.capture.take() {
            let _ = tokio::task::spawn_blocking(move || old.stop()).await;
        }
    }
    let (capture, mut started) = capture::spawn(request);
    let waited = tokio::select! {
        first = first_frame(&mut started) => Some(first),
        () = STOPS.asked() => None,
    };
    let Some(waited) = waited else {
        // The stop that is waiting for the session ends the share.
        let reason = stop_capture(capture, "The share was stopped".to_string()).await;
        log::info!("screenshare: the switch was stopped");
        return Err(reason);
    };
    let first = match waited {
        Ok(first) => first,
        Err(reason) => {
            let reason = stop_capture(capture, reason).await;
            log::warn!("screenshare: the switch failed: {reason}");
            if session.capture.is_none() {
                // Nothing is captured any more: end it, the way a closed
                // window does.
                crate::api::screenshare::emit_screenshare_event(
                    crate::api::screenshare::types::ScreenshareEvent::SourceClosed,
                );
            }
            return Err(reason);
        }
    };
    if let Some(old) = session.capture.take() {
        held = session.video.slot().take();
        let _ = tokio::task::spawn_blocking(move || old.stop()).await;
    }
    let new_slot = capture.slot();
    if let Some(native) = first {
        new_slot.seed(native);
    }
    session.video.set_slot(new_slot);
    session.capture = Some(capture);
    sources::set_sharing(chosen);

    match first {
        Some(native) => {
            if let Err(reason) = session.video.rebind(native, held).await {
                crate::api::screenshare::emit_screenshare_event(
                    crate::api::screenshare::types::ScreenshareEvent::SourceClosed,
                );
                return Err(reason);
            }
            // The window switched away from may have been minimised, which
            // viewers were told; this one is not.
            let participant = session.participant.lock().unwrap().clone();
            let attributes = HashMap::from([(PAUSED_ATTRIBUTE.to_string(), false.to_string())]);
            if let Err(e) = participant.set_attributes(attributes).await {
                log::warn!("screenshare: telling viewers paused=false: {e:?}");
            }
        }
        None => {
            drop(held);
            session.video.unpublish().await;
            log::info!("screenshare: waiting for the window to be opened");
            session.publisher = Some(tokio::spawn(publish_when_opened(
                session.video.clone(),
                started,
            )));
        }
    }

    let selection = AudioSelection::from(&source);
    if !selection.same_sound(&session.audio_selection) {
        if let Some(handle) = session.audio.take() {
            end_sound(&session.room, handle).await;
            session.audio = audio::start(
                &session.room,
                AudioCapture {
                    selection: selection.clone(),
                    track_name: AUDIO_TRACK_NAME.to_string(),
                    on_ended: None,
                },
            )
            .await;
        }
    }
    session.audio_selection = selection;
    log::info!("screenshare: switched");
    Ok(session.audio.is_some())
}

/// Take the share's sound off the room and stop capturing it.
async fn end_sound(room: &Room, handle: AudioCaptureHandle) {
    let track = handle.track();
    if let Err(e) = room.local_participant().unpublish_track(&track).await {
        log::warn!("screenshare: unpublishing the sound: {e:?}");
    }
    let _ = tokio::task::spawn_blocking(move || handle.terminate()).await;
}

/// The running share's picture as WebRTC reports it: what encoder it went
/// through, how many frames, and what held it back. For the log
/// ([`report_sending`]) and the benchmark.
pub(crate) async fn video_stats() -> Option<Vec<livekit::webrtc::stats::RtcStats>> {
    share_track().await?.1.get_stats().await.ok()
}

/// The running share's picture, and the track it goes out on.
async fn share_track() -> Option<(Arc<Video>, LocalVideoTrack)> {
    // Nothing of the session is held over an await: its capture is not
    // `Sync`, and the tasks asking run on any of the runtime's threads.
    let (participant, video) = {
        let slot = SESSION.lock().await;
        let session = slot.as_ref()?;
        (session.room.local_participant(), session.video.clone())
    };
    let sid = video.track.lock().await.clone()?;
    let publication = participant.get_track_publication(&sid)?;
    match publication.track()? {
        LocalTrack::Video(track) => Some((video, track)),
        _ => None,
    }
}

/// How often a GPU share asks whether the server has paused its picture.
#[cfg(gpu_encoder)]
const PAUSE_LOOK_EVERY: Duration = Duration::from_secs(1);

/// Tells the share's step-down whether the server has paused the picture,
/// which it does while nobody watches ([`StepDown::set_paused`]). Runs until
/// [`stop`] aborts it.
#[cfg(gpu_encoder)]
async fn follow_pause() {
    loop {
        tokio::time::sleep(PAUSE_LOOK_EVERY).await;
        let Some((video, track)) = share_track().await else {
            continue;
        };
        // One layer, and dynacast turns it off while nobody receives it.
        let layers = track.publishing_layers();
        let paused = !layers.is_empty() && layers.iter().all(|layer| !layer.active);
        if video.step.lock().unwrap().set_paused(paused, Instant::now()) {
            log::info!(
                "screenshare: {}",
                if paused {
                    "nobody watches, so the server paused the picture; its size holds"
                } else {
                    "someone watches again"
                }
            );
        }
    }
}

/// What each viewer receiving the share badly says of it
/// (`receive_report`), by the viewer's voice connection.
async fn viewers_in_trouble() -> HashMap<String, Report> {
    let slot = SESSION.lock().await;
    let Some(session) = slot.as_ref() else {
        return HashMap::new();
    };
    let share = session.room.local_participant().identity().to_string();
    session
        .room
        .remote_participants()
        .values()
        .filter_map(|viewer| {
            receive_report::of(&viewer.attributes(), &share)
                .map(|report| (viewer.identity().to_string(), report))
        })
        .collect()
}

/// Says in the log, every [`send_report::REPORT_EVERY`], what WebRTC sent of
/// the running share's picture: the sharer's side of a stutter a viewer
/// reports (`send_report`). And each viewer that says it receives the share
/// badly, when what it says changes: the share is one stream, so its
/// keyframes and rate are everyone's. Runs until [`stop`] aborts it; a
/// stretch with nothing sent, a minimised window's, is not said.
async fn report_sending() {
    let mut last: Option<(SendTotals, Instant)> = None;
    let mut troubled: HashMap<String, Report> = HashMap::new();
    let mut ticks = tokio::time::interval(send_report::REPORT_EVERY);
    ticks.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    // The first tick is at once, before anything is sent.
    ticks.tick().await;
    loop {
        ticks.tick().await;
        let Some(totals) = video_stats()
            .await
            .and_then(|stats| SendTotals::from_stats(&stats))
        else {
            continue;
        };
        let now = Instant::now();
        let before = last.as_ref();
        let sent_any = before.is_none_or(|(before, _)| before.frames_sent != totals.frames_sent);
        if sent_any {
            let seconds = before.map_or(send_report::REPORT_EVERY.as_secs_f64(), |(_, at)| {
                now.duration_since(*at).as_secs_f64()
            });
            log::info!(
                "{}",
                send_report::describe(before.map(|(totals, _)| totals), &totals, seconds)
            );
        }
        last = Some((totals, now));
        let viewers = viewers_in_trouble().await;
        for (viewer, report) in &viewers {
            if troubled.get(viewer) != Some(report) {
                log::info!(
                    "screenshare: a viewer ({viewer}) {}; the share is one stream, so its \
                     keyframes and rate are every viewer's",
                    report.describe()
                );
            }
        }
        for viewer in troubled.keys().filter(|v| !viewers.contains_key(*v)) {
            log::info!(
                "screenshare: a viewer ({viewer}) no longer says it receives the share badly"
            );
        }
        troubled = viewers;
    }
}

/// Asks the share's connection for one probe of its path as its pictures
/// begin to flow, and again on a connection made again ([`first_probe`]).
/// Runs until [`stop`] aborts it.
async fn probe_first_frames() {
    let mut first = FirstFrames::default();
    loop {
        tokio::time::sleep(first.next_look()).await;
        let Some(totals) = video_stats()
            .await
            .and_then(|stats| SendTotals::from_stats(&stats))
        else {
            continue;
        };
        let slot = SESSION.lock().await;
        let Some(session) = slot.as_ref() else {
            continue;
        };
        let cap_bps = f64::from(session.video.settings.lock().unwrap().bitrate) * 1e6;
        if !first.note(totals.frames_sent, totals.available_bps, cap_bps) {
            continue;
        }
        match session.room.probe_publisher() {
            Ok(()) => log::info!(
                "screenshare: pictures began to flow with {:.1} Mbps available of a {:.0} \
                 Mbps cap; probing the path",
                totals.available_bps / 1e6,
                cap_bps / 1e6
            ),
            Err(e) => log::warn!("screenshare: asking for a probe failed: {e:?}"),
        }
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
    let (capture, mut started) = capture::spawn(capture_request(
        &ShareSource::from(config),
        config.codec,
        config.fps,
        config.cursor,
        config.gpu_capture,
        participant,
    ));
    let first = match first_frame(&mut started).await {
        Ok(first) => first,
        Err(reason) => return Err(stop_capture(capture, reason).await),
    };

    let video = Arc::new_cyclic(|me| Video {
        me: me.clone(),
        participant: participant.clone(),
        slot: std::sync::Mutex::new(capture.slot()),
        settings: std::sync::Mutex::new(TrackSettings::from(config)),
        track: Mutex::new(None),
        #[cfg(gpu_encoder)]
        gpu: std::sync::Mutex::new(None),
        #[cfg(gpu_encoder)]
        step: Arc::new(std::sync::Mutex::new(StepDown::new(config.priority))),
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

/// What a capture of `source` is asked for, at the share's codec, rate and
/// cursor.
fn capture_request(
    source: &ShareSource,
    codec: VideoCodec,
    fps: u32,
    cursor: ShareCursor,
    gpu_capture: bool,
    participant: &SharedParticipant,
) -> CaptureRequest {
    CaptureRequest {
        source_type: sources::source_type(source.capture_full_screen),
        selected_index: source.selected_video_source_index,
        portal_choice: source.portal_choice.clone(),
        gpu_capture,
        codec,
        fps,
        capture_cursor: cursor != ShareCursor::Never,
        cursor_off_in_games: cursor == ShareCursor::Auto && source.capture_full_screen,
        on_paused: Some(announce_paused(participant.clone())),
        following: None,
    }
}

/// The size of a new capture's first frame, or None for a minimised window
/// that has none until it is opened. While the desktop's picker is up, the
/// first frame waits on a person. On an error the capture is the caller's to
/// stop.
async fn first_frame(started: &mut Started) -> Result<Option<Size>, String> {
    let mut limit = FIRST_FRAME_TIMEOUT;
    loop {
        match tokio::time::timeout(limit, started.recv()).await {
            Ok(Some(Progress::Picking)) => limit = PICKER_TIMEOUT,
            Ok(Some(Progress::Picked)) => limit = FIRST_FRAME_TIMEOUT,
            Ok(Some(Progress::FirstFrame(size))) => return Ok(Some(size)),
            Ok(Some(Progress::Waiting)) => return Ok(None),
            Ok(Some(Progress::Failed(reason))) => return Err(reason),
            Ok(None) => {
                return Err("The capture thread stopped before producing a frame".to_string())
            }
            Err(_) if limit == PICKER_TIMEOUT => {
                return Err("The desktop's picker had no answer".to_string())
            }
            Err(_) => {
                return Err(format!(
                    "No frames arrived from the selected source in {} seconds",
                    FIRST_FRAME_TIMEOUT.as_secs()
                ))
            }
        }
    }
}

/// What publishing the picture needs, none of it borrowed from the start.
struct Video {
    /// For a GPU encoder failing mid-share, which republishes from another
    /// thread and must not keep a stopped share alive to do it.
    #[cfg_attr(not(gpu_encoder), allow(dead_code))]
    me: Weak<Video>,
    participant: SharedParticipant,
    /// Where the capture hands its pictures; another capture's when the share
    /// is switched to another source ([`switch`]).
    slot: std::sync::Mutex<VideoSlot>,
    /// Changed by [`update`]; read each time the picture is published.
    settings: std::sync::Mutex<TrackSettings>,
    /// The published track, once there is one. Held for the whole of a
    /// publish, so a change made while a minimised window is opening waits
    /// for the first publish and then redoes it, rather than racing it.
    track: Mutex<Option<TrackSid>>,
    /// The picture's encoder and the source it feeds, while the GPU makes it.
    #[cfg(gpu_encoder)]
    gpu: std::sync::Mutex<Option<GpuPicture>>,
    /// Where a GPU picture is on its way down to what the connection
    /// carries: started again with each track, kept across the encoders
    /// opened for one.
    #[cfg(gpu_encoder)]
    step: Arc<std::sync::Mutex<StepDown>>,
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
    /// The size it is encoded at now.
    size: Size,
}

impl Video {
    /// The capture's pictures now — see [`switch`].
    fn slot(&self) -> VideoSlot {
        self.slot.lock().unwrap().clone()
    }

    fn set_slot(&self, slot: VideoSlot) {
        *self.slot.lock().unwrap() = slot;
    }

    /// Take the pictures of a capture just switched to, whose first frame is
    /// `native`. `held` is what the old capture fed. A raw source of the size
    /// the new picture needs is fed on, and viewers see no blink; anything else
    /// goes through [`change_picture`](Self::change_picture), which keeps a
    /// GPU picture's track and opens its encoder again on the new capture
    /// (on Windows, on the new capture's device). A share that never
    /// published, waiting on a minimised window, publishes now.
    async fn rebind(&self, native: Size, held: Option<(Feed, Size)>) -> Result<(), String> {
        {
            let mut track = self.track.lock().await;
            if track.is_none() {
                return self.publish_locked(&mut track, native).await;
            }
            let target = target_size(native, self.settings.lock().unwrap().max_height);
            if let Some((Feed::Raw(source), size)) = &held {
                if *size == target {
                    log::info!("screenshare: the new source fits the picture as it is");
                    self.slot().attach(Feed::Raw(source.clone()), target);
                    return Ok(());
                }
            }
        }
        // The old encoder is closed before another opens, which waits for
        // every hold on its feed to go.
        drop(held);
        self.change_picture().await
    }

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

    /// Takes the codec to publish in next, and says whether it changed. A
    /// share that fell back to VP9 tries the GPU again when H264 is asked
    /// for: the user asked, and a second failure falls back the same way.
    fn set_codec(&self, codec: VideoCodec) -> bool {
        let mut settings = self.settings.lock().unwrap();
        let changed = settings.codec != codec;
        settings.codec = codec;
        changed
    }

    /// The codec the picture goes out in, after any fall back.
    fn codec(&self) -> VideoCodec {
        self.settings.lock().unwrap().codec
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
            let native = self.slot().native()?;
            let target = {
                let mut step = self.step.lock().unwrap();
                step.fit(
                    gpu_target(target_size(native, settings.max_height)),
                    settings.fps,
                    settings.bitrate.saturating_mul(1_000_000),
                );
                step.size()
            };
            log::info!(
                "screenshare: re-encoding at {}x{}, {} fps, on the same track",
                target.width,
                target.height,
                settings.fps
            );
            let start = old.bitrate();
            self.slot().detach();
            drop(old);
            self.close_gpu().await;
            let fed = source.clone();
            let encoder = encoder_settings(codec, target, &settings, start);
            let step = self.step.clone();
            let on_failed = self.on_gpu_failed();
            let on_resize = self.on_step_resized();
            let opened = tokio::task::spawn_blocking(move || {
                GpuFeed::open(&fed, encoder, step, on_failed, on_resize)
            })
            .await
            .map_err(|e| format!("The GPU encoder did not open: {e}"))
            .and_then(|opened| opened);
            match opened {
                Ok(feed) => {
                    let feed = Arc::new(feed);
                    self.slot().attach(Feed::Gpu(feed.clone()), target);
                    *self.gpu.lock().unwrap() = Some(GpuPicture {
                        source,
                        feed,
                        published_fps,
                        published_bitrate,
                        size: target,
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
            .slot()
            .native()
            .ok_or("No frame has been captured to size the picture by")?;
        self.slot().detach();
        #[cfg(gpu_encoder)]
        self.close_gpu().await;
        if let Err(e) = self.participant().unpublish_track(&old).await {
            log::warn!("screenshare: unpublishing the old picture: {e:?}");
        }
        self.publish_locked(&mut track, native).await
    }

    /// Take the picture down until there is one to show: a share switched to
    /// a minimised window has none, and publishes when the window is opened
    /// (`publish_when_opened`), as a share started on one does. Left up, a
    /// change made meanwhile — the menu, a codec step, a reconnect — would
    /// look for a frame there is none of, and end the share.
    async fn unpublish(&self) {
        let mut track = self.track.lock().await;
        let Some(old) = track.take() else {
            return;
        };
        self.slot().detach();
        #[cfg(gpu_encoder)]
        self.close_gpu().await;
        if let Err(e) = self.participant().unpublish_track(&old).await {
            log::warn!("screenshare: unpublishing the picture: {e:?}");
        }
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
            .slot()
            .native()
            .ok_or("No frame has been captured to size the picture by")?;
        self.slot().detach();
        #[cfg(gpu_encoder)]
        self.close_gpu().await;
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
        // share on the GPU"): from Rift's own encoder, and as VP9 if it will
        // not open.
        #[cfg(gpu_encoder)]
        while let Some(codec) = GpuCodec::for_share(settings.codec) {
            let target = gpu_target(target);
            let published = if codec == GpuCodec::H265
                && !server_takes_h265(&self.participant().enabled_publish_codecs())
            {
                Err("this server does not take H265".to_string())
            } else if encoder::encodes_itself(codec) {
                self.publish_from_gpu(target, codec, &settings).await
            } else {
                Err(format!("no GPU here encodes {codec}"))
            };
            match published {
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
        self.slot().attach(Feed::Raw(source.clone()), target);
        let sid = publish_video_track(&self.participant(), source, &settings, None).await?;
        *track = Some(sid);
        announce_picture(&self.participant(), target, settings.fps);
        Ok(())
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
        // A new track starts at the top: WebRTC's estimate starts over with it.
        let step = {
            let mut step = self.step.lock().unwrap();
            *step = StepDown::new(settings.priority);
            step.fit(
                target,
                settings.fps,
                settings.bitrate.saturating_mul(1_000_000),
            );
            self.step.clone()
        };
        let on_failed = self.on_gpu_failed();
        let on_resize = self.on_step_resized();
        let feed = tokio::task::spawn_blocking(move || {
            GpuFeed::open(&fed, encoder, step, on_failed, on_resize)
        })
        .await
        .map_err(|e| format!("The GPU encoder did not open: {e}"))??;
        log::info!("screenshare: encoding on {}", feed.name());
        let feed = Arc::new(feed);
        self.slot().attach(Feed::Gpu(feed.clone()), target);
        let sid = publish_video_track(
            &self.participant(),
            source.clone(),
            settings,
            Some(&encoder),
        )
        .await?;
        *self.gpu.lock().unwrap() = Some(GpuPicture {
            source,
            feed,
            published_fps: settings.fps,
            published_bitrate: settings.bitrate,
            size: target,
        });
        Ok(sid)
    }

    /// Close the GPU picture's encoder, if there is one, before another opens:
    /// a card at its limit of encoder sessions refuses a second, and the share
    /// falls to VP9. A republish left the old one open until the new one was
    /// published. The slot has let the feed go by now, but the processing
    /// thread may still hold it for the picture it is sending, so this waits
    /// for that too, for a second at most.
    #[cfg(gpu_encoder)]
    async fn close_gpu(&self) {
        let Some(picture) = self.gpu.lock().unwrap().take() else {
            return;
        };
        let started = Instant::now();
        let mut feed = picture.feed;
        loop {
            match Arc::try_unwrap(feed) {
                Ok(alone) => {
                    let waited = started.elapsed();
                    // Joins the encoder's thread, which finishes what it holds.
                    drop(alone);
                    if waited >= Duration::from_millis(1) {
                        log::info!(
                            "screenshare: waited {} ms for the old encoder to be let go",
                            waited.as_millis()
                        );
                    }
                    return;
                }
                Err(held) if started.elapsed() < Duration::from_secs(1) => {
                    feed = held;
                    tokio::time::sleep(Duration::from_millis(2)).await;
                }
                Err(_) => {
                    log::warn!(
                        "screenshare: the old encoder is still held; the new one opens beside it"
                    );
                    return;
                }
            }
        }
    }

    /// Give up on this codec for the rest of this share, and say so: H265
    /// for H264 from the same GPU, and H264 for VP9 on the CPU.
    #[cfg(gpu_encoder)]
    fn fall_back(&self, reason: &str) -> TrackSettings {
        let from = self.settings.lock().unwrap().codec;
        let (next, event) = if from == VideoCodec::H265 && encoder::encodes_itself(GpuCodec::H264) {
            (VideoCodec::H264, ScreenshareEvent::H265FellBack)
        } else {
            (VideoCodec::VP9, ScreenshareEvent::EncoderFellBack)
        };
        log::warn!("screenshare: {reason}; sharing as {next:?} instead");
        let mut settings = self.settings.lock().unwrap();
        settings.codec = next;
        crate::api::screenshare::emit_screenshare_event(event);
        *settings
    }

    /// What the processing thread calls when the share steps to another
    /// size ([`StepDown`]): open an encoder at it on the same track.
    #[cfg(gpu_encoder)]
    fn on_step_resized(&self) -> Box<dyn Fn() + Send + Sync> {
        let me = self.me.clone();
        let runtime = tokio::runtime::Handle::current();
        Box::new(move || {
            let me = me.clone();
            runtime.spawn(async move {
                let Some(video) = me.upgrade() else {
                    return;
                };
                // A republish or a move that held the track meanwhile opened
                // its encoder at the size the step asks for, or started the
                // ladder over: nothing to open again.
                let encoded = video.gpu.lock().unwrap().as_ref().map(|gpu| gpu.size);
                if encoded == Some(video.step.lock().unwrap().size()) {
                    return;
                }
                match video.reopen_gpu().await {
                    Some(Ok(())) => {}
                    Some(Err(reason)) => {
                        log::warn!("screenshare: {reason}");
                        crate::api::screenshare::emit_screenshare_event(
                            ScreenshareEvent::SourceClosed,
                        );
                    }
                    None => log::info!("screenshare: the picture is no longer the GPU's to step"),
                }
            });
        })
    }

    /// What the processing thread calls when the encoder stops working
    /// mid-share: publish again in the next codec down
    /// ([`fall_back`](Self::fall_back)), so the picture never stays black.
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
/// Whether a server's list of the codecs it takes has H265 on it. One with
/// H265 off, or too old to have it, does not refuse a track in H265: viewers
/// just get no picture (`CALLS.md`, *Stepping a share down*).
#[cfg(gpu_encoder)]
fn server_takes_h265(codecs: &[String]) -> bool {
    codecs.iter().any(|codec| codec == "video/h265")
}

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
        h264_high: encoder::SEND_H264_HIGH,
        gpu_capture: settings.gpu_capture,
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
            Progress::Waiting | Progress::Picking | Progress::Picked => {}
            Progress::Failed(reason) => {
                log::info!("screenshare: gave up waiting: {reason}");
                return;
            }
            Progress::FirstFrame(native) => {
                if let Err(reason) = video.rebind(native, None).await {
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
/// shared window is minimised or gone and when it is back. Called from the
/// capture thread, so the request is handed to the runtime rather than awaited
/// there: to one task, which sends the latest word whenever it changes. A task
/// for each could finish out of order, and leave a live share showing paused.
fn announce_paused(participant: SharedParticipant) -> Box<dyn Fn(bool) + Send> {
    let (said, mut heard) = tokio::sync::watch::channel(false);
    tokio::runtime::Handle::current().spawn(async move {
        // Over once the capture lets go of the sender.
        while heard.changed().await.is_ok() {
            let paused = *heard.borrow_and_update();
            let participant = participant.lock().unwrap().clone();
            let attributes = HashMap::from([(PAUSED_ATTRIBUTE.to_string(), paused.to_string())]);
            if let Err(e) = participant.set_attributes(attributes).await {
                log::warn!("screenshare: telling viewers paused={paused}: {e:?}");
            }
        }
    });
    Box::new(move |paused| {
        let _ = said.send(paused);
    })
}

/// Stop a capture off the async runtime, and hand back the reason it is being
/// stopped so the error path reads as one expression.
async fn stop_capture(capture: Capture, reason: String) -> String {
    let _ = tokio::task::spawn_blocking(move || capture.stop()).await;
    reason
}

#[cfg(all(test, gpu_encoder))]
mod tests {
    use super::server_takes_h265;

    #[test]
    fn h265_goes_out_only_where_the_server_lists_it() {
        let on = ["video/vp8".to_string(), "video/h265".to_string()];
        assert!(server_takes_h265(&on));
        assert!(!server_takes_h265(&on[..1]), "H265 off");
        assert!(!server_takes_h265(&[]), "a server too old to say");
    }
}
