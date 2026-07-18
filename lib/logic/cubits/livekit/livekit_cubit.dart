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
import '../../services/sound_service.dart';

part 'livekit_state.dart';
part 'livekit_media_controls.dart';
part 'livekit_participants.dart';
part 'livekit_screenshare.dart';
part 'livekit_room_events.dart';
part 'livekit_voice_activity.dart';

/// Cubit managing LiveKit room connections, participants, and media controls.
class LiveKitCubit extends Cubit<LiveKitState>
    with
        _MediaControlsMixin,
        _ParticipantMixin,
        _ScreenshareMixin,
        _RoomEventsMixin,
        _VoiceActivityMixin {
  @override
  final AppCubit _appCubit;
  final TokenCubit _tokenCubit;
  @override
  final ServerCubit? _serverCubit;
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
  // Connection
  // ──────────────────────────────────────────────────────────

  /// Connects to a LiveKit channel. Server context is resolved internally via
  /// [_serverCubit]; callers only supply the channel and media preferences.
  Future<void> connectToChannel({
    required String channelId,
    bool? micEnabled,
    bool? cameraEnabled,
  }) async {
    final hadRoom = state.room != null;
    final wasConnecting = state.connectionState == LiveKitConnectionState.connecting;

    // Emit 'connecting' before cleanup so the RoomDisconnectedEvent fired during
    // _cleanupRoom is not misread as an unexpected disconnect and doesn't clear
    // the new channel ID.
    emit(
      state.copyWith(
        connectionState: LiveKitConnectionState.connecting,
        currentChannelId: channelId,
        clearError: true,
      ),
    );

    if (hadRoom || wasConnecting) await _cleanupRoom();

    emit(state.copyWith(clearRoom: true));

    final server = _serverCubit?.state.selectedServer;
    if (server == null) {
      emit(state.copyWith(
        connectionState: LiveKitConnectionState.error,
        error: 'No server selected',
      ));
      return;
    }
    final livekitUrl = server.livekitUrl;
    if (livekitUrl == null) {
      emit(state.copyWith(
        connectionState: LiveKitConnectionState.error,
        error: 'No LiveKit URL configured for this server',
      ));
      return;
    }

    String livekitToken;
    final cached = _tokenCubit.getValidToken(server.supabaseUrl, channelId);
    if (cached != null) {
      livekitToken = cached.token;
    } else {
      final response = await _serverCubit!.getChannelToken(channelId);
      if (!response.success) {
        debugPrint('[LiveKit] Failed to get channel token: ${response.error}');
        emit(state.copyWith(
          connectionState: LiveKitConnectionState.error,
          error: response.error ?? 'Failed to get channel token',
        ));
        return;
      }
      livekitToken = response.data['token'] as String;
      _tokenCubit.saveToken(server.supabaseUrl, channelId, livekitToken);
    }

    final room = Room(
      roomOptions: RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioCaptureOptions: _buildAudioCaptureOptions(),
      ),
    );
    _setupRoomListeners(room);

    try {
      final useMicEnabled = micEnabled ?? state.isMicEnabled;
      final useCameraEnabled = cameraEnabled ?? state.isCameraEnabled;
      final joinMicEnabled = _shouldTransmitMic(
        micEnabled: useMicEnabled,
        deafened: state.isDeafened,
      );

      await room.connect(
        livekitUrl,
        livekitToken,
        fastConnectOptions: FastConnectOptions(
          microphone: TrackOption(enabled: joinMicEnabled),
          camera: TrackOption(enabled: useCameraEnabled),
        ),
      );

      emit(state.copyWith(
        connectionState: LiveKitConnectionState.connected,
        room: room,
        isMicEnabled: useMicEnabled,
        isCameraEnabled: useCameraEnabled,
      ));

      await _syncMicrophoneTransmission();
      SoundService.instance.playJoin();
      _syncParticipants();
      _applyStoredSettings();
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] room.connect() threw: $e');
      emit(state.copyWith(
        connectionState: LiveKitConnectionState.error,
        error: 'Failed to connect: $e',
      ));
      await room.disconnect();
      await room.dispose();
    }
  }

  /// Disconnects from the current room.
  Future<void> disconnect() async {
    if (_screenshareCubit?.state.isSharing == true) {
      await _screenshareCubit?.stopScreenShare();
    }

    SoundService.instance.playLeave();
    _appCubit.setParticipants([]);
    _appCubit.setSelectedChannelId(null);

    emit(state.copyWith(
      connectionState: LiveKitConnectionState.disconnected,
      clearChannelId: true,
      clearError: true,
      participants: [],
    ));

    await _cleanupRoom();
    emit(state.copyWith(clearRoom: true));
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
    emit(state.copyWith(
      participants: allParticipants,
      isCameraEnabled:
          room.localParticipant?.isCameraEnabled() ?? state.isCameraEnabled,
      isScreenSharing:
          room.localParticipant?.isScreenShareEnabled() ?? state.isScreenSharing,
    ));

    // Sync participant info to AppCubit for the UI.
    final infos = allParticipants.map((p) {
      final moderation =
          ParticipantInfo.moderationFromMetadata(p.metadata);
      return ParticipantInfo(
        identity: p.identity,
        userId: ParticipantIdentity.userIdOf(p.identity),
        name: p.name,
        isSpeaking: p.isSpeaking,
        isMicrophoneEnabled: p.isMicrophoneEnabled(),
        isCameraEnabled: p.isCameraEnabled(),
        isLocal: p is LocalParticipant,
        isScreenshare: ParticipantIdentity.isScreenshare(p.identity),
        isServerMuted: moderation.muted,
        isServerDeafened: moderation.deafened,
      );
    }).toList();

    _appCubit.setParticipants(_dedupeByUser(infos));
  }

  /// Collapses a user who is present from multiple devices into a single
  /// roster entry (one per user, and one per user's screenshare). The kept
  /// entry prefers the local participant, then a speaking one, then a
  /// mic-enabled one, so the surviving row reflects the "active" device.
  List<ParticipantInfo> _dedupeByUser(List<ParticipantInfo> infos) {
    final byKey = <String, ParticipantInfo>{};
    for (final info in infos) {
      final key = '${info.userId}|${info.isScreenshare}';
      final existing = byKey[key];
      if (existing == null || _isBetterEntry(info, existing)) {
        byKey[key] = info;
      }
    }
    return byKey.values.toList();
  }

  bool _isBetterEntry(ParticipantInfo candidate, ParticipantInfo current) {
    int rank(ParticipantInfo p) =>
        (p.isLocal ? 4 : 0) +
        (p.isSpeaking ? 2 : 0) +
        (p.isMicrophoneEnabled ? 1 : 0);
    return rank(candidate) > rank(current);
  }

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

  bool _shouldTransmitMic({required bool micEnabled, required bool deafened}) {
    if (!micEnabled || deafened) return false;
    final pttEnabled = _appCubit.state.pushToTalkEnabled;
    final hasKeybind = _appCubit.state.pushToTalkKeyId != null;
    if (!pttEnabled) return true;
    if (!hasKeybind) return false;
    return state.isPushToTalkPressed;
  }

  @override
  Future<void> _syncMicrophoneTransmission({bool syncParticipants = false}) async {
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

  Future<void> _cleanupRoom() async {
    await _stopVoiceActivityMonitor();

    final room = state.room;
    if (room == null) return;

    try {
      if (room.connectionState == ConnectionState.connected ||
          room.connectionState == ConnectionState.connecting) {
        await room.disconnect();
      }
      for (final l in _listeners) {
        try {
          l.dispose();
        } catch (e) {
          HelperMethods.printDebug('Error disposing listener: $e');
        }
      }
      _listeners.clear();
      emit(state.copyWith(subscribedScreenshares: {}));
      await room.dispose();
    } catch (e) {
      HelperMethods.printDebug('Error during room cleanup: $e');
    }
  }

  @override
  Future<void> close() async {
    await _appSubscription?.cancel();
    await _cleanupRoom();
    return super.close();
  }
}
