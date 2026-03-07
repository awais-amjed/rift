import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../../../data/classes/participant_info.dart';
import '../../../data/repositories/server_repository.dart';
import '../app/app_cubit.dart';
import '../screenshare/screenshare_cubit.dart';

part 'livekit_state.dart';

/// Cubit managing LiveKit room connections, participants, and media controls.
class LiveKitCubit extends Cubit<LiveKitState> {
  final ServerRepository _repository;
  final AppCubit _appCubit;
  ScreenshareCubit? _screenshareCubit;
  final List<EventsListener<RoomEvent>> _listeners = [];

  LiveKitCubit({
    required ServerRepository repository,
    required AppCubit appCubit,
    ScreenshareCubit? screenshareCubit,
  }) : _repository = repository,
       _appCubit = appCubit,
       _screenshareCubit = screenshareCubit,
       super(const LiveKitState());

  /// Set the screenshare cubit for automatic cleanup on disconnect
  void setScreenshareCubit(ScreenshareCubit cubit) {
    _screenshareCubit = cubit;
  }

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
      // If the user was deafened before joining, join with mic off
      final joinMicEnabled = state.isDeafened ? false : useMicEnabled;

      await room.connect(
        livekitUrl,
        livekitToken,
        fastConnectOptions: FastConnectOptions(
          microphone: TrackOption(enabled: joinMicEnabled),
          camera: TrackOption(enabled: useCameraEnabled),
        ),
      );

      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.connected,
          room: room,
          isMicEnabled: useMicEnabled,
          isCameraEnabled: useCameraEnabled,
          // preserve isDeafened — user set it before joining
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
    // Stop screenshare if active
    if (_screenshareCubit?.state.isSharing == true) {
      debugPrint('Stopping screenshare due to channel disconnect...');
      await _screenshareCubit?.stopScreenShare();
    }

    // Clear participants immediately
    _appCubit.setParticipants([]);
    _appCubit.setSelectedChannelId(null);

    // Update state to disconnected before cleanup — preserve mic/deafen prefs
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

  /// Toggle microphone on/off. Works even when not in a channel so the
  /// preference is saved and applied on the next connect.
  Future<void> toggleMicrophone() async {
    final room = state.room;

    if (state.isDeafened) {
      // Un-deafen restores mic — undeafening also unmutes
      await _setDeafened(false);
      return;
    }

    final next = !state.isMicEnabled;
    if (room != null) {
      await room.localParticipant?.setMicrophoneEnabled(next);
    }
    _appCubit.setAudioEnabled(next);
    emit(state.copyWith(isMicEnabled: next));
    if (room != null) _syncParticipants();
  }

  /// Toggle deafen on/off (like Discord).
  /// Deafening: mutes mic + disables all remote audio tracks locally.
  /// Un-deafening: re-enables audio + restores mic.
  /// Works even when not in a channel so the preference is saved.
  Future<void> toggleDeafen() async {
    await _setDeafened(!state.isDeafened);
  }

  Future<void> _setDeafened(bool deafened) async {
    final room = state.room;

    if (deafened) {
      if (room != null) {
        // Mute mic
        await room.localParticipant?.setMicrophoneEnabled(false);

        // Unsubscribe from all remote audio tracks + silence any already-active ones
        for (final participant in room.remoteParticipants.values) {
          for (final pub in participant.audioTrackPublications) {
            final track = pub.track;
            if (track != null) {
              track.mediaStreamTrack.enabled = false;
            }
            await pub.unsubscribe();
          }
        }
      }
      _appCubit.setAudioEnabled(false);
      emit(state.copyWith(isDeafened: true, isMicEnabled: false));
    } else {
      if (room != null) {
        // Re-subscribe all remote audio tracks
        for (final participant in room.remoteParticipants.values) {
          final setting =
              _appCubit.state.participantSettings[participant.identity];
          final isMuted = setting?.muted ?? false;

          for (final pub in participant.audioTrackPublications) {
            await pub.subscribe();

            final track = pub.track;
            if (track == null) continue;

            if (isMuted) {
              track.mediaStreamTrack.enabled = false;
            } else {
              track.mediaStreamTrack.enabled = true;
              final volume = setting?.volume ?? 1.0;
              if (volume != 1.0) {
                try {
                  await rtc.Helper.setVolume(volume, track.mediaStreamTrack);
                } catch (e) {
                  debugPrint('setVolume error: $e');
                }
              }
            }
          }
        }

        // Restore mic
        await room.localParticipant?.setMicrophoneEnabled(true);
      }
      _appCubit.setAudioEnabled(true);
      emit(state.copyWith(isDeafened: false, isMicEnabled: true));
    }

    if (room != null) _syncParticipants();
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

  /// Mute a participant for everyone in the room (requires is_channel_manager).
  /// Calls the server-side edge function which uses the LiveKit Server API.
  Future<bool> muteParticipantForEveryone({
    required String supabaseUrl,
    required String token,
    required String participantIdentity,
    required bool muted,
  }) async {
    final channelId = state.currentChannelId;
    if (channelId == null) return false;

    final response = await _repository.muteParticipant(
      supabaseUrl,
      token,
      channelId: channelId,
      participantIdentity: participantIdentity,
      muted: muted,
    );

    if (!response.success) {
      debugPrint('muteParticipantForEveryone error: ${response.error}');
    }
    return response.success;
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
          track.mediaStreamTrack.enabled = !muted;
        }
      }
    }

    _appCubit.setParticipantSetting(identity, muted: muted);
  }

  /// Set local volume for a remote participant's audio (for this user only).
  Future<void> setParticipantVolume(String identity, double volume) async {
    final room = state.room;
    if (room == null) return;

    final participant = room.remoteParticipants[identity];
    if (participant != null) {
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track != null) {
          try {
            await rtc.Helper.setVolume(volume, track.mediaStreamTrack);
          } catch (e) {
            debugPrint('setParticipantVolume error: $e');
          }
        }
      }
    }

    _appCubit.setParticipantSetting(identity, volume: volume);
  }

  /// Subscribe to a participant's screenshare video track.
  Future<void> subscribeToScreenshare(String identity) async {
    final room = state.room;
    if (room == null) return;

    final participant = room.remoteParticipants[identity];
    if (participant == null) {
      debugPrint('Participant $identity not found');
      return;
    }

    // Find screenshare video track publication
    for (final pub in participant.videoTrackPublications) {
      if (pub.source == TrackSource.screenShareVideo) {
        try {
          await pub.subscribe();
          debugPrint('✓ Subscribed to screenshare from $identity');
          _syncParticipants();
        } catch (e) {
          debugPrint('✗ Failed to subscribe to screenshare: $e');
        }
        return;
      }
    }

    debugPrint('No screenshare track found for $identity');
  }

  /// Unsubscribe from a participant's screenshare video track.
  Future<void> unsubscribeFromScreenshare(String identity) async {
    final room = state.room;
    if (room == null) return;

    final participant = room.remoteParticipants[identity];
    if (participant == null) return;

    // Find screenshare video track publication
    for (final pub in participant.videoTrackPublications) {
      if (pub.source == TrackSource.screenShareVideo) {
        try {
          await pub.unsubscribe();
          debugPrint('✓ Unsubscribed from screenshare from $identity');
          _syncParticipants();
        } catch (e) {
          debugPrint('✗ Failed to unsubscribe from screenshare: $e');
        }
        return;
      }
    }
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
              // preserve isMicEnabled and isDeafened
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

    // Don't derive mic/camera/screen state from LiveKit when deafened —
    // deafen forces mic off at the WebRTC level but the cubit state should
    // reflect what the user had set before deafening.
    emit(
      state.copyWith(
        participants: allParticipants,
        isMicEnabled: state.isDeafened
            ? state.isMicEnabled
            : (room.localParticipant?.isMicrophoneEnabled() ??
                  state.isMicEnabled),
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
            isScreenshare: p.identity.endsWith('_screenshare'),
          ),
        )
        .toList();

    _appCubit.setParticipants(infos);
  }

  /// Re-applies persisted mute/volume settings to all current remote participants.
  void _applyStoredSettings() {
    final room = state.room;
    if (room == null) return;

    final settings = _appCubit.state.participantSettings;
    for (final entry in settings.entries) {
      final identity = entry.key;
      final setting = entry.value;

      final participant = room.remoteParticipants[identity];
      if (participant == null) continue;

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
