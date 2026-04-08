import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../../../data/classes/participant_info.dart';
import '../app/app_cubit.dart';
import '../screenshare/screenshare_cubit.dart';
import '../server/server_cubit.dart';
import '../token/token_cubit.dart';
import '../../services/sound_service.dart';

part 'livekit_state.dart';
part 'livekit_media_controls.dart';
part 'livekit_participants.dart';
part 'livekit_screenshare.dart';
part 'livekit_room_events.dart';

/// Cubit managing LiveKit room connections, participants, and media controls.
class LiveKitCubit extends Cubit<LiveKitState>
    with _MediaControlsMixin, _ParticipantMixin, _ScreenshareMixin, _RoomEventsMixin {
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
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
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
      debugPrint('[LiveKit] room.connect() threw: $e');
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
    final infos = allParticipants
        .map((p) => ParticipantInfo(
              identity: p.identity,
              name: p.name,
              isSpeaking: p.isSpeaking,
              isMicrophoneEnabled: p.isMicrophoneEnabled(),
              isCameraEnabled: p.isCameraEnabled(),
              isLocal: p is LocalParticipant,
              isScreenshare: p.identity.endsWith('_screenshare'),
            ))
        .toList();

    _appCubit.setParticipants(infos);
  }

  void _onAppStateChanged(AppState appState) {
    final previous = _lastAppState;
    _lastAppState = appState;
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
    await room.localParticipant?.setMicrophoneEnabled(shouldTransmit);
    if (syncParticipants) _syncParticipants();
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
    for (final entry in settings.entries) {
      final identity = entry.key;
      final setting = entry.value;

      final participant = room.remoteParticipants[identity];
      if (participant == null) continue;

      // Screenshare participants have their audio managed separately.
      if (identity.endsWith('_screenshare')) continue;

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
          debugPrint('Error disposing listener: $e');
        }
      }
      _listeners.clear();
      emit(state.copyWith(subscribedScreenshares: {}));
      await room.dispose();
    } catch (e) {
      debugPrint('Error during room cleanup: $e');
    }
  }

  @override
  Future<void> close() async {
    await _appSubscription?.cancel();
    await _cleanupRoom();
    return super.close();
  }
}
