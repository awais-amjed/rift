import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../../../data/classes/channel.dart';
import '../../../data/classes/participant_info.dart';
import '../../../data/participant_identity.dart';
import '../app/app_cubit.dart';
import '../screenshare/screenshare_cubit.dart';
import '../server/server_cubit.dart';
import '../token/token_cubit.dart';
import '../../helper_methods.dart';
import '../../services/audio_devices.dart';
import '../../services/call_foreground_service.dart';
import '../../services/connection_failure.dart';
import '../../services/level_throttle.dart';
import '../../services/mic_tap_format.dart';
import '../../services/participant_roster.dart';
import '../../services/participant_video.dart';
import '../../services/pcm_level.dart';
import '../../services/pip_focus.dart';
import '../../services/pip_service.dart';
import '../../services/room_tiles.dart';
import '../../services/serial_queue.dart';
import '../../services/sound_service.dart';
import '../../services/speech_detector.dart';
import '../../services/voice_signal.dart';

part 'livekit_state.dart';
part 'livekit_connection.dart';
part 'livekit_media_controls.dart';
part 'livekit_participants.dart';
part 'livekit_screenshare.dart';
part 'livekit_room_events.dart';
part 'livekit_voice_activity.dart';

/// Cubit managing LiveKit room connections, participants, and media controls.
class LiveKitCubit extends Cubit<LiveKitState>
    with
        _LiveKitConnectionMixin,
        _MediaControlsMixin,
        _ParticipantMixin,
        _ScreenshareMixin,
        _RoomEventsMixin,
        _VoiceActivityMixin {
  @override
  final AppCubit _appCubit;
  @override
  final TokenCubit _tokenCubit;
  @override
  final ServerCubit? _serverCubit;
  @override
  ScreenshareCubit? _screenshareCubit;
  @override
  final List<EventsListener<RoomEvent>> _listeners = [];
  StreamSubscription<AppState>? _appSubscription;
  AppState _lastAppState;

  LiveKitCubit({
    required AppCubit appCubit,
    required TokenCubit tokenCubit,
    ServerCubit? serverCubit,
    ScreenshareCubit? screenshareCubit,
  }) : _appCubit = appCubit,
       _tokenCubit = tokenCubit,
       _serverCubit = serverCubit,
       _screenshareCubit = screenshareCubit,
       _lastAppState = appCubit.state,
       super(const LiveKitState()) {
    _appSubscription = _appCubit.stream.listen(_onAppStateChanged);
  }

  void setScreenshareCubit(ScreenshareCubit cubit) {
    _screenshareCubit = cubit;
  }

  /// Keeps the call notification's mute button honest.
  ///
  /// Here rather than in [toggleMicrophone] because the mic is muted from more
  /// than one place — the toggle, deafen, a moderator — and the shade should
  /// say the same thing as the app whichever it was.
  @override
  void onChange(Change<LiveKitState> change) {
    super.onChange(change);
    if (change.currentState.isMicEnabled != change.nextState.isMicEnabled) {
      unawaited(
        CallForegroundService.micChanged(change.nextState.isMicEnabled),
      );
    }
    _syncPictureInPicture(change.nextState);
  }

  /// Tells Android whether leaving the app should shrink it to a floating
  /// window rather than put the call away.
  ///
  /// Armed on what there is to *see*, not on being in a call: a window with
  /// nothing in it is a black rectangle over whatever the user left to do, and
  /// an audio call is already represented in the notification shade. Cheap
  /// enough to recompute on every emit — a call is a handful of participants —
  /// and [PipService.setArmed] drops the ones that change nothing.
  void _syncPictureInPicture(LiveKitState state) {
    final connected = state.connectionState == LiveKitConnectionState.connected;
    final focus = connected
        ? pipFocus(
            roomVoiceTiles(state.participants),
            isLocal: (p) => p is LocalParticipant,
            isSpeaking: (p) => p.isSpeaking,
            hasVideo: (tile) =>
                ParticipantVideo.activePublication(
                  tile.participant.videoTrackPublications,
                  isScreenshare: tile.isScreenshare,
                )?.track !=
                null,
          )
        : null;
    unawaited(PipService.instance.setArmed(focus != null));
  }

  // ──────────────────────────────────────────────────────────
  // Internal helpers
  // ──────────────────────────────────────────────────────────

  @override
  void _syncParticipants() {
    final room = state.room;
    if (room == null) return;

    final allParticipants = <Participant>[
      if (room.localParticipant != null) room.localParticipant!,
      ...room.remoteParticipants.values,
    ];

    // Don't derive mic state from LiveKit when deafened — deafen forces the
    // WebRTC track off but the cubit state should reflect the pre-deafen value.
    emit(
      state.copyWith(
        participants: allParticipants,
        isCameraEnabled:
            room.localParticipant?.isCameraEnabled() ?? state.isCameraEnabled,
        isScreenSharing:
            room.localParticipant?.isScreenShareEnabled() ??
            state.isScreenSharing,
      ),
    );

    // Sync participant info to AppCubit for the UI.
    final infos = allParticipants.map((p) {
      final moderation = ParticipantInfo.moderationFromMetadata(p.metadata);
      return ParticipantInfo(
        identity: p.identity,
        userId: ParticipantIdentity.userIdOf(p.identity),
        name: p.name,
        // Only the *local* user is measured here. Doing it per remote track
        // meant one audio analyser per participant — CPU that scales with
        // channel size to duplicate work the SFU already does. Remote speaking
        // comes from LiveKit's active-speaker detection, tuned server-side via
        // `audio.active_level` / `update_interval` (see docs/livekit_tuning).
        //
        // The local user stays client-side: one analyser on our own mic, and
        // `update_interval` is a latency floor you'd feel on your own
        // indicator.
        isSpeaking: p is LocalParticipant ? localIsSpeaking : p.isSpeaking,
        isMicrophoneEnabled: p.isMicrophoneEnabled(),
        isCameraEnabled: p.isCameraEnabled(),
        isLocal: p is LocalParticipant,
        isScreenshare: ParticipantIdentity.isScreenshare(p.identity),
        isServerMuted: moderation.muted,
        isServerDeafened: moderation.deafened,
      );
    }).toList();

    _appCubit.setParticipants(ParticipantRoster.dedupeByUser(infos));
    _syncSelfModeration(infos);
  }

  /// Picks our own moderation state out of the roster and acts on a change.
  ///
  /// It has to be acted on, not merely displayed. Revoking the microphone makes
  /// LiveKit unpublish the track, so lifting the mute has to republish it —
  /// otherwise the member stays silent until they happen to toggle their mic,
  /// which is what "the admin unmuted me and nothing happened" looked like.
  /// Lifting a server deafen likewise has to hand the remote audio back.
  void _syncSelfModeration(List<ParticipantInfo> infos) {
    ParticipantInfo? me;
    for (final info in infos) {
      if (info.isLocal && !info.isScreenshare) {
        me = info;
        break;
      }
    }
    if (me == null) return;

    if (me.isServerMuted == state.isServerMuted &&
        me.isServerDeafened == state.isServerDeafened) {
      return;
    }

    final wasDeafened = state.isDeafenedEffective;
    emit(
      state.copyWith(
        isServerMuted: me.isServerMuted,
        isServerDeafened: me.isServerDeafened,
      ),
    );
    unawaited(_reactToSelfModeration(wasDeafened: wasDeafened));
  }

  /// Brings the local media back in line after our moderation state moved. The
  /// user's own toggles are untouched, so what they get back is what they
  /// themselves last chose — a mic they had muted stays muted.
  Future<void> _reactToSelfModeration({required bool wasDeafened}) async {
    if (wasDeafened && !state.isDeafenedEffective) {
      await _restoreRemoteAudio();
    } else if (!wasDeafened && state.isDeafenedEffective) {
      await _silenceRemoteAudio();
    }
    await _syncMicrophoneTransmission(syncParticipants: true);
  }

  /// Collapses a user who is present from multiple devices into a single
  /// roster entry (one per user, and one per user's screenshare). The kept
  /// entry prefers the local participant, then a speaking one, then a

  void _onAppStateChanged(AppState appState) {
    final previous = _lastAppState;
    _lastAppState = appState;

    // Audio-processing toggles: recreate the mic track so the new capture
    // constraints apply mid-call.
    final audioProcessingChanged =
        previous.noiseSuppression != appState.noiseSuppression ||
        previous.echoCancellation != appState.echoCancellation ||
        previous.autoGainControl != appState.autoGainControl;
    if (audioProcessingChanged) {
      unawaited(_refreshMicrophoneCapture());
    }

    final pttChanged =
        previous.pushToTalkEnabled != appState.pushToTalkEnabled ||
        previous.pushToTalkKeyId != appState.pushToTalkKeyId;
    if (!pttChanged) return;

    final shouldResetPressed =
        !appState.pushToTalkEnabled || appState.pushToTalkKeyId == null;
    if (shouldResetPressed) {
      // Turning push-to-talk off mid-release must not leave a timer behind to
      // undo the mic state this is about to settle.
      _cancelPushToTalkRelease();
      if (state.isPushToTalkPressed) {
        emit(state.copyWith(isPushToTalkPressed: false));
      }
    }
    unawaited(_syncMicrophoneTransmission());
  }

  @override
  bool _shouldTransmitMic({bool? micEnabled}) {
    // `micEnabled` overrides only the user's own toggle, for the connect path
    // where the stored preference is passed in before it reaches state. Their
    // own deafen and any moderation always come from state.
    if (!(micEnabled ?? state.isMicEnabled)) return false;
    if (state.isDeafenedEffective || state.isServerMuted) return false;
    final pttEnabled = _appCubit.state.pushToTalkEnabled;
    final hasKeybind = _appCubit.state.pushToTalkKeyId != null;
    if (!pttEnabled) return true;
    if (!hasKeybind) return false;
    return state.isPushToTalkPressed;
  }

  @override
  Future<void> _syncMicrophoneTransmission({
    bool syncParticipants = false,
  }) async {
    final room = state.room;
    if (room == null) return;
    final shouldTransmit = _shouldTransmitMic();
    // Pass the current capture options so a fresh mic track (created on
    // unmute) always picks up the latest noise-suppression / echo / AGC
    // settings, not the ones frozen into RoomOptions at connect time.
    await room.localParticipant?.setMicrophoneEnabled(
      shouldTransmit,
      audioCaptureOptions: _buildAudioCaptureOptions(),
    );
    // Re-bind the level monitor to the (possibly new) mic track.
    await _updateVoiceActivityMonitor();
    if (syncParticipants) _syncParticipants();
  }

  /// Builds mic capture options from the persisted audio-processing settings.
  /// [deviceId] is intentionally left unset — input-device selection is
  /// handled globally via `Hardware.instance.selectAudioInput`.
  @override
  AudioCaptureOptions _buildAudioCaptureOptions() {
    final settings = _appCubit.state;
    return AudioCaptureOptions(
      noiseSuppression: settings.noiseSuppression,
      echoCancellation: settings.echoCancellation,
      autoGainControl: settings.autoGainControl,
    );
  }

  /// Rebuilds mic capture, for after the input device changes.
  ///
  /// WebRTC binds the device when the track is created, so a track that is
  /// already publishing keeps capturing from the old microphone however the
  /// selection changes underneath it.
  ///
  /// There is deliberately no matching hook for the output device. Playout is
  /// not tied to a track this side owns: `Hardware.selectAudioOutput` reaches
  /// libwebrtc's `SetPlayoutDevice`, which already stops playout, sets the
  /// device, and initialises and starts it again when something is playing.
  /// This used to rejoin the channel on every output change, on the belief
  /// that mid-call switching was unsupported — it isn't, and the rejoin only
  /// tore the connection down underneath a device change that was already in
  /// flight on the worker thread.
  Future<void> refreshAudioInput() => _refreshMicrophoneCapture();

  /// Re-publishes the mic track so changed capture options take effect during
  /// a live call. WebRTC bakes these constraints in at track creation, so the
  /// track must be recreated — stop it, then let the normal transmission sync
  /// bring it back with the new options.
  @override
  Future<void> _refreshMicrophoneCapture() async {
    final room = state.room;
    if (room == null) return;
    if (state.connectionState != LiveKitConnectionState.connected) return;
    await room.localParticipant?.setMicrophoneEnabled(false);
    await _syncMicrophoneTransmission();
  }

  /// Applies HIGH video quality to screenshare tracks from remote participants.
  @override
  void _applyScreenshareQualitySettings(Participant participant) {
    if (participant is! RemoteParticipant) return;
    for (final pub in participant.videoTrackPublications) {
      if (pub.source == TrackSource.screenShareVideo) {
        pub.setVideoQuality(VideoQuality.HIGH);
      }
    }
  }

  /// Re-applies persisted mute/volume settings to current remote participants.
  @override
  void _applyStoredSettings() {
    final room = state.room;
    if (room == null) return;

    final settings = _appCubit.state.participantSettings;
    for (final participant in room.remoteParticipants.values) {
      final identity = participant.identity;

      // Screenshare participants have their audio managed separately.
      if (ParticipantIdentity.isScreenshare(identity)) continue;

      // Per-user local mute/volume is keyed by user id, not the raw identity
      // (which carries a per-device segment).
      final setting = settings[ParticipantIdentity.userIdOf(identity)];
      if (setting == null) continue;

      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track == null) continue;
        if (setting.muted) {
          track.mediaStreamTrack.enabled = false;
        } else {
          track.mediaStreamTrack.enabled = true;
          if (setting.volume != 1.0) {
            rtc.Helper.setVolume(setting.volume, track.mediaStreamTrack);
          }
        }
      }
    }
  }

  @override
  Future<void> close() async {
    _cancelPushToTalkRelease();
    await _appSubscription?.cancel();
    await _cleanupRoom();
    await _micLevelController.close();
    return super.close();
  }
}
