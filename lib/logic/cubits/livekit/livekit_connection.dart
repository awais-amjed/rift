part of 'livekit_cubit.dart';

/// Joining and leaving a LiveKit room, and tearing the room down cleanly.
///
/// Connecting always cleans up any previous room first, and emits
/// `connecting` before it does — otherwise the disconnect event fired during
/// cleanup reads as an unexpected drop and clears the new channel.
mixin _LiveKitConnectionMixin on Cubit<LiveKitState> {
  AppCubit get _appCubit;
  TokenCubit get _tokenCubit;
  ServerCubit? get _serverCubit;
  List<EventsListener<RoomEvent>> get _listeners;

  ScreenshareCubit? get _screenshareCubit;

  /// Guards [disconnect] against re-entering itself — see its doc comment.
  bool _disconnecting = false;

  /// Implemented by the cubit and its other mixins.
  void _syncParticipants();
  void setupRoomListeners(Room room);
  void _applyStoredSettings();
  Future<void> _stopVoiceActivityMonitor();

  Future<void> _syncMicrophoneTransmission();
  bool _shouldTransmitMic({required bool micEnabled, required bool deafened});
  AudioCaptureOptions _buildAudioCaptureOptions();

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

    if (hadRoom || wasConnecting) await _cleanupRoom();

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
      roomOptions: RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioCaptureOptions: _buildAudioCaptureOptions(),
      ),
    );
    setupRoomListeners(room);

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
        ),
      );

      await _syncMicrophoneTransmission();
      SoundService.instance.playJoin();
      _syncParticipants();
      _applyStoredSettings();
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] room.connect() threw: $e');
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

  /// Runs the failed join again, against the channel that failed.
  ///
  /// Drops the cached channel token first. A token the server has just refused
  /// — expired, or minted before the member's access changed — is one of the
  /// likelier reasons a join fails, and [connectToChannel] prefers the cache,
  /// so retrying without evicting it would fail identically forever. That is
  /// what made leaving for another channel and coming back the only cure: it
  /// was never the round trip that helped, only the fresh token at the end of
  /// it. Re-minting one costs a single edge-function call when the cause was
  /// something else, which is worth it to make the button always mean
  /// something.
  Future<void> retryConnection() async {
    final channelId = state.currentChannelId;
    if (channelId == null) return;
    _tokenCubit.invalidateToken(channelId);
    await connectToChannel(channelId: channelId);
  }

  /// Disconnects from the current room.
  ///
  /// Runs at most once at a time. Clearing the selected channel below is the
  /// same signal `MainContent` listens on to leave a call, so this re-enters
  /// itself on every leave: the second call starts as soon as the first
  /// awaits, and both then tear down the same [Room].
  Future<void> disconnect() async {
    if (_disconnecting) return;
    _disconnecting = true;
    try {
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
    } finally {
      _disconnecting = false;
    }
  }

  Future<void> _cleanupRoom() async {
    // Claim the room and its listeners before the first await. Connecting and
    // disconnecting both land here, so two teardowns can otherwise overlap and
    // disconnect and dispose the same Room twice over.
    final room = state.room;
    if (room == null) {
      await _stopVoiceActivityMonitor();
      return;
    }
    emit(state.copyWith(clearRoom: true));
    final listeners = List.of(_listeners);
    _listeners.clear();

    await _stopVoiceActivityMonitor();

    try {
      if (room.connectionState == ConnectionState.connected ||
          room.connectionState == ConnectionState.connecting) {
        await room.disconnect();
      }
      for (final l in listeners) {
        try {
          l.dispose();
        } catch (e) {
          HelperMethods.printDebug('Error disposing listener: $e');
        }
      }
      emit(state.copyWith(subscribedScreenshares: {}));
      await room.dispose();
    } catch (e) {
      HelperMethods.printDebug('Error during room cleanup: $e');
    }
  }
}
