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

/// Cubit managing LiveKit room connections, participants, and media controls.
class LiveKitCubit extends Cubit<LiveKitState> {
  final AppCubit _appCubit;
  final TokenCubit _tokenCubit;
  final ServerCubit? _serverCubit;
  ScreenshareCubit? _screenshareCubit;
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
  // Connection Management
  // ──────────────────────────────────────────────────────────

  /// Connects to a LiveKit channel. Server context is resolved internally via
  /// [_serverCubit]; callers only supply the channel and media preferences.
  Future<void> connectToChannel({
    required String channelId,
    bool? micEnabled,
    bool? cameraEnabled,
  }) async {
    final hadRoom = state.room != null;
    final wasConnecting =
        state.connectionState == LiveKitConnectionState.connecting;

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

    // If already connected or connecting, clean up the old room first.
    if (hadRoom || wasConnecting) {
      await _cleanupRoom();
    }

    emit(state.copyWith(clearRoom: true));

    final server = _serverCubit?.state.selectedServer;
    if (server == null) {
      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.error,
          error: 'No server selected',
        ),
      );
      return;
    }
    final livekitUrl = server.livekitUrl;
    if (livekitUrl == null) {
      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.error,
          error: 'No LiveKit URL configured for this server',
        ),
      );
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
        emit(
          state.copyWith(
            connectionState: LiveKitConnectionState.error,
            error: response.error ?? 'Failed to get channel token',
          ),
        );
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

      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.connected,
          room: room,
          isMicEnabled: useMicEnabled,
          isCameraEnabled: useCameraEnabled,
          // preserve isDeafened — user set it before joining
        ),
      );

      await _syncMicrophoneTransmission();

      SoundService.instance.playJoin();

      _syncParticipants();
      _applyStoredSettings();
    } catch (e) {
      debugPrint('[LiveKit] room.connect() threw: $e');
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

  /// Disconnects from the current room.
  Future<void> disconnect() async {
    if (_screenshareCubit?.state.isSharing == true) {
      await _screenshareCubit?.stopScreenShare();
    }

    SoundService.instance.playLeave();

    _appCubit.setParticipants([]);
    _appCubit.setSelectedChannelId(null);

    emit(
      state.copyWith(
        connectionState: LiveKitConnectionState.disconnected,
        clearChannelId: true,
        clearError: true,
        participants: [],
      ),
    );

    await _cleanupRoom();
    emit(state.copyWith(clearRoom: true));
  }

  // ──────────────────────────────────────────────────────────
  // Media Controls
  // ──────────────────────────────────────────────────────────

  /// Toggles microphone. If deafened, un-deafens instead (restoring mic).
  Future<void> toggleMicrophone() async {
    if (state.isDeafened) {
      await _setDeafened(false);
      return;
    }

    final next = !state.isMicEnabled;
    _appCubit.setAudioEnabled(next);
    emit(state.copyWith(isMicEnabled: next));
    await _syncMicrophoneTransmission(syncParticipants: true);
  }

  /// Toggles deafen: mutes mic and silences all remote audio, or reverses that.
  Future<void> toggleDeafen() async {
    await _setDeafened(!state.isDeafened);
  }

  Future<void> _setDeafened(bool deafened) async {
    final room = state.room;

    if (deafened) {
      if (room != null) {
        await room.localParticipant?.setMicrophoneEnabled(false);

        // Unsubscribe and silence all remote audio tracks.
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
        // Re-subscribe all remote audio tracks, restoring per-participant settings.
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
      await _syncMicrophoneTransmission();
    }

    if (room != null) _syncParticipants();
  }

  Future<void> setPushToTalkPressed(bool pressed) async {
    if (state.isPushToTalkPressed == pressed) return;

    emit(state.copyWith(isPushToTalkPressed: pressed));
    await _syncMicrophoneTransmission(syncParticipants: true);
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

  /// Mutes/unmutes a participant for everyone in the room (requires is_channel_manager).
  Future<bool> muteParticipantForEveryone({
    required String participantIdentity,
    required bool muted,
  }) async {
    final channelId = state.currentChannelId;
    if (channelId == null) return false;

    final serverCubit = _serverCubit;
    if (serverCubit == null) return false;

    final response = await serverCubit.muteParticipant(
      channelId: channelId,
      participantIdentity: participantIdentity,
      muted: muted,
    );

    if (!response.success) {
      debugPrint('muteParticipantForEveryone error: ${response.error}');
    }
    return response.success;
  }

  /// Locally mutes/unmutes a remote participant's audio (this user only).
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

  /// Sets the local volume for a remote participant's audio (this user only).
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

  /// Subscribes to a participant's screenshare tracks.
  Future<void> subscribeToScreenshare(String identity) async {
    final room = state.room;
    if (room == null) return;

    final participant = room.remoteParticipants[identity];
    if (participant == null) {
      debugPrint('Participant $identity not found');
      return;
    }

    var subscribedAny = false;

    for (final pub in participant.videoTrackPublications) {
      if (pub.source == TrackSource.screenShareVideo) {
        try {
          await pub.subscribe();
          pub.setVideoQuality(VideoQuality.HIGH);
          debugPrint('✓ Subscribed to screenshare video from $identity');
          subscribedAny = true;
        } catch (e) {
          debugPrint('✗ Failed to subscribe to screenshare video: $e');
        }
      }
    }

    for (final pub in participant.audioTrackPublications) {
      if (pub.source == TrackSource.screenShareAudio) {
        try {
          await pub.subscribe();
          debugPrint('✓ Subscribed to screenshare audio from $identity');
          subscribedAny = true;
        } catch (e) {
          debugPrint('✗ Failed to subscribe to screenshare audio: $e');
        }
      }
    }

    if (subscribedAny) {
      final updatedSubscriptions = Set<String>.from(
        state.subscribedScreenshares,
      )..add(identity);
      emit(state.copyWith(subscribedScreenshares: updatedSubscriptions));

      _syncParticipants();
    } else {
      debugPrint('No screenshare tracks found for $identity');
    }
  }

  /// Unsubscribes from a participant's screenshare tracks.
  Future<void> unsubscribeFromScreenshare(String identity) async {
    final room = state.room;
    if (room == null) return;

    final participant = room.remoteParticipants[identity];
    if (participant == null) return;

    var unsubscribedAny = false;

    for (final pub in participant.videoTrackPublications) {
      if (pub.source == TrackSource.screenShareVideo) {
        try {
          await pub.unsubscribe();
          debugPrint('✓ Unsubscribed from screenshare video from $identity');
          unsubscribedAny = true;
        } catch (e) {
          debugPrint('✗ Failed to unsubscribe from screenshare video: $e');
        }
      }
    }

    for (final pub in participant.audioTrackPublications) {
      if (pub.source == TrackSource.screenShareAudio) {
        try {
          await pub.unsubscribe();
          debugPrint('✓ Unsubscribed from screenshare audio from $identity');
          unsubscribedAny = true;
        } catch (e) {
          debugPrint('✗ Failed to unsubscribe from screenshare audio: $e');
        }
      }
    }

    if (unsubscribedAny) {
      final updatedSubscriptions = Set<String>.from(
        state.subscribedScreenshares,
      )..remove(identity);
      emit(state.copyWith(subscribedScreenshares: updatedSubscriptions));

      _syncParticipants();
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
        final identity = e.participant.identity;
        if (identity.endsWith('_screenshare')) {
          SoundService.instance.playStreamStarted();
        } else {
          SoundService.instance.playJoin();
        }
        _syncParticipants();
        _applyStoredSettings();
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        final identity = e.participant.identity;
        if (identity.endsWith('_screenshare')) {
          SoundService.instance.playStreamEnded();
        } else {
          SoundService.instance.playLeave();
        }
        _syncParticipants();
      })
      ..on<TrackPublishedEvent>((e) {
        _syncParticipants();
        _applyStoredSettings();

        if (e.participant.identity.endsWith('_screenshare')) {
          if (!state.subscribedScreenshares.contains(e.participant.identity)) {
            // Prevent auto-subscription to unsubscribed screenshares.
            if (e.publication.subscribed) {
              e.publication.unsubscribe();
            }
          } else {
            if (e.publication.source == TrackSource.screenShareVideo) {
              _applyScreenshareQualitySettings(e.participant);
            }
          }
        } else {
          _applyScreenshareQualitySettings(e.participant);
        }
      })
      ..on<TrackSubscribedEvent>((e) {
        _syncParticipants();

        if (e.participant.identity.endsWith('_screenshare')) {
          if (e.publication.source == TrackSource.screenShareVideo) {
            if (state.subscribedScreenshares.contains(e.participant.identity)) {
              e.publication.setVideoQuality(VideoQuality.HIGH);
            } else {
              e.publication.unsubscribe();
            }
          } else if (e.publication.source == TrackSource.screenShareAudio) {
            if (!state.subscribedScreenshares.contains(e.participant.identity)) {
              e.publication.unsubscribe();
            }
          }
        } else {
          if (e.publication.source == TrackSource.screenShareVideo) {
            e.publication.setVideoQuality(VideoQuality.HIGH);
          }
        }
      })
      ..on<TrackUnpublishedEvent>((e) => _syncParticipants())
      ..on<ActiveSpeakersChangedEvent>((e) => _syncParticipants())
      ..on<TrackMutedEvent>((e) => _syncParticipants())
      ..on<TrackUnmutedEvent>((e) => _syncParticipants())
      ..on<RoomDisconnectedEvent>((e) {
        // Only handle unexpected disconnects; intentional disconnects set state beforehand.
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

  Future<void> _syncMicrophoneTransmission({bool syncParticipants = false}) async {
    final room = state.room;
    if (room == null) return;

    final shouldTransmit = _shouldTransmitMic(
      micEnabled: state.isMicEnabled,
      deafened: state.isDeafened,
    );
    await room.localParticipant?.setMicrophoneEnabled(shouldTransmit);

    if (syncParticipants) {
      _syncParticipants();
    }
  }

  /// Applies HIGH video quality to screenshare tracks from remote participants.
  void _applyScreenshareQualitySettings(Participant participant) {
    if (participant is! RemoteParticipant) return;

    for (final pub in participant.videoTrackPublications) {
      if (pub.source == TrackSource.screenShareVideo) {
        pub.setVideoQuality(VideoQuality.HIGH);
        debugPrint(
          '✓ Applied HIGH quality to screenshare from ${participant.identity}',
        );
      }
    }
  }

  /// Re-applies persisted mute/volume settings to current remote participants.
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
