import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../data/classes/participant_info.dart';
import '../../../data/repositories/server_repository.dart';
import '../app/app_cubit.dart';

part 'livekit_state.dart';

/// Cubit managing LiveKit room connections, participants, and media controls.
class LiveKitCubit extends Cubit<LiveKitState> {
  final ServerRepository _repository;
  final AppCubit _appCubit;
  final List<EventsListener<RoomEvent>> _listeners = [];

  LiveKitCubit({
    required ServerRepository repository,
    required AppCubit appCubit,
  }) : _repository = repository,
       _appCubit = appCubit,
       super(const LiveKitState());

  // ──────────────────────────────────────────────────────────
  // Connection Management
  // ──────────────────────────────────────────────────────────

  /// Connect to a LiveKit channel.
  Future<void> connectToChannel({
    required String channelId,
    required String supabaseUrl,
    required String token,
    required String livekitUrl,
    bool? micEnabled,
    bool? cameraEnabled,
  }) async {
    // If we're already connected or connecting, disconnect first
    if (state.room != null ||
        state.connectionState == LiveKitConnectionState.connecting) {
      await _cleanupRoom();
    }

    emit(
      state.copyWith(
        connectionState: LiveKitConnectionState.connecting,
        currentChannelId: channelId,
        clearError: true,
        clearRoom: true,
      ),
    );

    // Get LiveKit token from server
    final response = await _repository.getChannelToken(
      supabaseUrl,
      token,
      channelId,
    );

    if (!response.success) {
      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.error,
          error: response.error ?? 'Failed to get channel token',
        ),
      );
      return;
    }

    final livekitToken = response.data['token'] as String;
    final room = Room(
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );

    _setupRoomListeners(room);

    try {
      final useMicEnabled = micEnabled ?? state.isMicEnabled;
      final useCameraEnabled = cameraEnabled ?? state.isCameraEnabled;

      await room.connect(
        livekitUrl,
        livekitToken,
        fastConnectOptions: FastConnectOptions(
          microphone: TrackOption(enabled: useMicEnabled),
          camera: TrackOption(enabled: useCameraEnabled),
        ),
      );

      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.connected,
          room: room,
          isMicEnabled: useMicEnabled,
          isCameraEnabled: useCameraEnabled,
        ),
      );

      _syncParticipants();
      _applyStoredSettings();
    } catch (e) {
      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.error,
          error: 'Failed to connect: $e',
        ),
      );
      await room.disconnect();
      await room.dispose();
    }
  }

  /// Disconnect from the current room.
  Future<void> disconnect() async {
    // Clear participants immediately
    _appCubit.setParticipants([]);
    _appCubit.setSelectedChannelId(null);

    // Update state to disconnected before cleanup
    emit(
      state.copyWith(
        connectionState: LiveKitConnectionState.disconnected,
        clearChannelId: true,
        clearError: true,
        participants: [],
      ),
    );

    // Clean up room asynchronously
    await _cleanupRoom();

    // Ensure room is cleared from state
    emit(state.copyWith(clearRoom: true));
  }

  // ──────────────────────────────────────────────────────────
  // Media Controls
  // ──────────────────────────────────────────────────────────

  /// Toggle microphone on/off.
  Future<void> toggleMicrophone() async {
    final room = state.room;
    if (room == null) return;

    final next = !state.isMicEnabled;
    await room.localParticipant?.setMicrophoneEnabled(next);
    _appCubit.setAudioEnabled(next);
    emit(state.copyWith(isMicEnabled: next));
    _syncParticipants();
  }

  /// Toggle camera on/off.
  Future<void> toggleCamera() async {
    final room = state.room;
    if (room == null) return;

    final next = !state.isCameraEnabled;
    await room.localParticipant?.setCameraEnabled(next);
    _appCubit.setVideoEnabled(next);
    emit(state.copyWith(isCameraEnabled: next));
    _syncParticipants();
  }

  /// Locally mute/unmute a remote participant's audio (for this user only).
  Future<void> setParticipantMute(String identity, bool muted) async {
    final room = state.room;
    if (room == null) return;

    final participant = room.remoteParticipants[identity];
    if (participant != null) {
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track != null) {
          if (muted) {
            await track.disable();
          } else {
            await track.enable();
          }
        }
      }
    }

    _appCubit.setParticipantSetting(identity, muted: muted);
  }

  /// Set local volume for a remote participant's audio (for this user only).
  void setParticipantVolume(String identity, double volume) {
    _appCubit.setParticipantSetting(identity, volume: volume);
  }

  /// Toggle screen sharing on/off.
  Future<void> toggleScreenShare({
    ScreenShareCaptureOptions? captureOptions,
  }) async {
    final room = state.room;
    if (room == null) return;

    final next = !state.isScreenSharing;

    try {
      await room.localParticipant?.setScreenShareEnabled(
        next,
        screenShareCaptureOptions:
            captureOptions ??
            ScreenShareCaptureOptions(useiOSBroadcastExtension: false),
      );
      emit(state.copyWith(isScreenSharing: next));
      _syncParticipants();
    } catch (e) {
      emit(state.copyWith(error: 'Screen share failed: $e'));
    }
  }

  // ──────────────────────────────────────────────────────────
  // Internal Methods
  // ──────────────────────────────────────────────────────────

  void _setupRoomListeners(Room room) {
    final listener = room.createListener();
    _listeners.add(listener);

    listener
      ..on<ParticipantConnectedEvent>((e) {
        _syncParticipants();
        _applyStoredSettings();
      })
      ..on<ParticipantDisconnectedEvent>((e) => _syncParticipants())
      ..on<TrackPublishedEvent>((e) {
        _syncParticipants();
        _applyStoredSettings();
      })
      ..on<TrackUnpublishedEvent>((e) => _syncParticipants())
      ..on<ActiveSpeakersChangedEvent>((e) => _syncParticipants())
      ..on<TrackMutedEvent>((e) => _syncParticipants())
      ..on<TrackUnmutedEvent>((e) => _syncParticipants())
      ..on<RoomDisconnectedEvent>((e) {
        // Only handle unexpected disconnections
        if (state.connectionState == LiveKitConnectionState.connected) {
          _appCubit.setSelectedChannelId(null);
          emit(
            state.copyWith(
              connectionState: LiveKitConnectionState.disconnected,
              clearRoom: true,
              participants: [],
            ),
          );
        }
      });
  }

  void _syncParticipants() {
    final room = state.room;
    if (room == null) return;

    final allParticipants = <Participant>[
      if (room.localParticipant != null) room.localParticipant!,
      ...room.remoteParticipants.values,
    ];

    // Update state with current participants
    emit(
      state.copyWith(
        participants: allParticipants,
        isMicEnabled:
            room.localParticipant?.isMicrophoneEnabled() ?? state.isMicEnabled,
        isCameraEnabled:
            room.localParticipant?.isCameraEnabled() ?? state.isCameraEnabled,
        isScreenSharing:
            room.localParticipant?.isScreenShareEnabled() ??
            state.isScreenSharing,
      ),
    );

    // Sync to AppCubit for UI display
    final infos = allParticipants
        .map(
          (p) => ParticipantInfo(
            identity: p.identity,
            name: p.name,
            isSpeaking: p.isSpeaking,
            isMicrophoneEnabled: p.isMicrophoneEnabled(),
            isCameraEnabled: p.isCameraEnabled(),
            isLocal: p is LocalParticipant,
          ),
        )
        .toList();

    _appCubit.setParticipants(infos);
  }

  /// Re-applies persisted mute settings to all current remote participants.
  void _applyStoredSettings() {
    final room = state.room;
    if (room == null) return;

    final settings = _appCubit.state.participantSettings;
    for (final entry in settings.entries) {
      final identity = entry.key;
      final setting = entry.value;
      if (!setting.muted) continue;

      final participant = room.remoteParticipants[identity];
      if (participant == null) continue;

      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track != null) {
          track.disable();
        }
      }
    }
  }

  Future<void> _cleanupRoom() async {
    final room = state.room;
    if (room == null) return;

    try {
      // Disconnect gracefully if still connected
      if (room.connectionState == ConnectionState.connected ||
          room.connectionState == ConnectionState.connecting) {
        await room.disconnect();
      }

      // Dispose listeners after disconnect to prevent stream cancellation errors
      for (final l in _listeners) {
        try {
          l.dispose();
        } catch (e) {
          // Ignore listener disposal errors
          debugPrint('Error disposing listener: $e');
        }
      }
      _listeners.clear();

      // Finally dispose the room
      await room.dispose();
    } catch (e) {
      // Ignore disposal errors as we're cleaning up anyway
      debugPrint('Error during room cleanup: $e');
    }
  }

  @override
  Future<void> close() {
    _cleanupRoom();
    return super.close();
  }
}
