import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../../../data/classes/participant_info.dart';
import '../../../data/participant_identity.dart';
import '../app/app_cubit.dart';
import '../screenshare/screenshare_cubit.dart';
import '../server/server_cubit.dart';
import '../token/token_cubit.dart';
import '../../helper_methods.dart';
import '../../services/connection_failure.dart';
import '../../services/participant_roster.dart';
import '../../services/serial_queue.dart';
import '../../services/sound_service.dart';
import '../../services/speech_detector.dart';

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
        // The local user stays client-side: that analyser already runs for the
        // noise gate, so it costs nothing extra, and `update_interval` is a
        // latency floor you'd feel on your own indicator.
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

    // Voice-activity threshold change: attach/detach or retune the gate.
    if (previous.voiceActivityThreshold != appState.voiceActivityThreshold) {
      unawaited(_updateVoiceActivityMonitor());
    }

    final pttChanged =
        previous.pushToTalkEnabled != appState.pushToTalkEnabled ||
        previous.pushToTalkKeyId != appState.pushToTalkKeyId;
    if (!pttChanged) return;

    final shouldResetPressed =
        !appState.pushToTalkEnabled || appState.pushToTalkKeyId == null;
    if (shouldResetPressed && state.isPushToTalkPressed) {
      emit(state.copyWith(isPushToTalkPressed: false));
    }
    unawaited(_syncMicrophoneTransmission());
  }

  @override
  bool _shouldTransmitMic({required bool micEnabled, required bool deafened}) {
    if (!micEnabled || deafened) return false;
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
    final shouldTransmit = _shouldTransmitMic(
      micEnabled: state.isMicEnabled,
      deafened: state.isDeafened,
    );
    // Pass the current capture options so a fresh mic track (created on
    // unmute) always picks up the latest noise-suppression / echo / AGC
    // settings, not the ones frozen into RoomOptions at connect time.
    await room.localParticipant?.setMicrophoneEnabled(
      shouldTransmit,
      audioCaptureOptions: _buildAudioCaptureOptions(),
    );
    // Re-bind the voice-activity gate to the (possibly new) mic track.
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

  /// Re-publishes the mic track so changed capture options take effect during
  /// a live call. WebRTC bakes these constraints in at track creation, so the
  /// track must be recreated — stop it, then let the normal transmission sync
  /// bring it back with the new options.
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
    await _appSubscription?.cancel();
    await _cleanupRoom();
    await _micLevelController.close();
    return super.close();
  }
}
