part of 'livekit_cubit.dart';

/// Joining and leaving a LiveKit room, and tearing the room down cleanly.
///
/// Over the mixin budget and still one job: every step of a join depends on
/// the one before it, and splitting them would scatter a single sequence.
///
/// Connecting always cleans up any previous room first, and emits
/// `connecting` before it does — otherwise the disconnect event fired during
/// cleanup reads as an unexpected drop and clears the new channel.
mixin _LiveKitConnectionMixin on Cubit<LiveKitState>, _E2EEMixin {
  AppCubit get _appCubit;
  TokenCubit get _tokenCubit;

  /// Implemented by the cubit and its other mixins.
  void _syncParticipants();
  void setupRoomListeners(Room room);
  void _applyStoredSettings();

  Future<void> _syncMicrophoneTransmission();

  /// Implemented by the cubit: tells the room what this client is doing that
  /// it cannot see for itself.
  Future<void> _publishSelfState();

  /// Implemented by [_MediaControlsMixin]; needed here so the call
  /// notification's Mute button has something to press.
  Future<void> toggleMicrophone();
  Future<void> _refreshMicrophoneCapture();

  /// Both implemented by [_LiveKitLeaveMixin]. Joining needs them because a
  /// join that fails partway has to undo itself, and because being moved to
  /// another channel is a leave followed by a join.
  Future<void> disconnect();
  Future<void> _cleanupRoom();
  bool _shouldTransmitMic({bool? micEnabled});
  AudioCaptureOptions _buildAudioCaptureOptions();

  /// Puts the user's saved input and output devices in force for this call,
  /// and reports whether the input moved.
  ///
  /// This belongs to joining and nowhere else. WebRTC's audio device module
  /// neither enumerates nor accepts a selection until it is running, which it
  /// only is once a room is connected — so applying the choice at app startup,
  /// as this used to, ran before there was anything to apply it to and left
  /// every call on whatever the platform picked.
  ///
  /// A device that cannot be opened is not a reason to fail the join. It is
  /// reported and the call continues on the platform default, which is audible
  /// and recoverable; the picker in settings says the same thing in the UI
  /// when the choice is made by hand.
  Future<bool> _applySavedAudioDevices() async {
    try {
      final applied = await AudioDevices.applySaved(
        inputId: _appCubit.state.inputDeviceId,
        outputId: _appCubit.state.outputDeviceId,
      );
      return applied.input;
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] saved audio device refused: $e');
      return false;
    }
  }

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
        clearFailure: true,
      ),
    );

    if (hadRoom || wasConnecting) await _cleanupRoom();

    emit(state.copyWith(clearRoom: true));

    final server = _serverCubit?.state.selectedServer;
    if (server == null) {
      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.error,
          failure: const ConnectionFailure.noServer(),
        ),
      );
      return;
    }
    final livekitUrl = server.livekitUrl;
    if (livekitUrl == null) {
      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.error,
          failure: const ConnectionFailure.noLiveKitUrl(),
        ),
      );
      return;
    }

    // A cached token belongs to the account it was minted for, and this
    // device may have been signed into more than one. Without the user in the
    // lookup, signing in as someone else reuses the previous account's token
    // and joins the room as them.
    final userId = server.user?.id;
    if (userId == null) {
      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.error,
          failure: const ConnectionFailure.noServer(),
        ),
      );
      return;
    }

    String livekitToken;
    final cached = _tokenCubit.getValidToken(
      server.supabaseUrl,
      channelId,
      userId,
    );
    if (cached != null) {
      livekitToken = cached.token;
    } else {
      final response = await _serverCubit!.getChannelToken(channelId);
      if (!response.success) {
        debugPrint('[LiveKit] Failed to get channel token: ${response.error}');
        emit(
          state.copyWith(
            connectionState: LiveKitConnectionState.error,
            failure: response.errorCode == ErrorCode.voiceChannelFull
                ? ConnectionFailure.callFull(response.error)
                : ConnectionFailure.tokenRequest(response.error),
          ),
        );
        return;
      }
      livekitToken = response.data['token'] as String;
      _tokenCubit.saveToken(
        server.supabaseUrl,
        channelId,
        userId,
        livekitToken,
      );
    }

    // The key before the room. A call joined without one would connect, work,
    // and be readable by the server — the single thing this is here to stop —
    // so there is no unencrypted fallback path to take by accident.
    final e2ee = await _prepareE2EE(channelId);
    if (e2ee == null) {
      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.error,
          failure: const ConnectionFailure.noChannelKey(),
        ),
      );
      return;
    }

    final room = Room(
      roomOptions: RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioCaptureOptions: _buildAudioCaptureOptions(),
        e2eeOptions: e2ee,
      ),
    );
    setupRoomListeners(room);

    try {
      final useMicEnabled = micEnabled ?? state.isMicEnabled;
      final useCameraEnabled = cameraEnabled ?? state.isCameraEnabled;
      final joinMicEnabled = _shouldTransmitMic(micEnabled: useMicEnabled);

      await room.connect(
        livekitUrl,
        livekitToken,
        fastConnectOptions: FastConnectOptions(
          microphone: TrackOption(enabled: joinMicEnabled),
          camera: TrackOption(enabled: useCameraEnabled),
        ),
      );

      // Whoever is already here, plus us. A participant whose key is not
      // registered is one nobody can hear, so this happens before the state
      // says connected.
      await _registerAllParticipantKeys(room);
      // And from here on, a key rotated by somebody being removed has to reach
      // this call rather than waiting for a rejoin.
      _watchKeyRotations(server, channelId);

      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.connected,
          room: room,
          connectedAt: DateTime.now(),
          isMicEnabled: useMicEnabled,
          isCameraEnabled: useCameraEnabled,
        ),
      );

      // Only now can the saved devices be applied — see
      // [_applySavedAudioDevices]. If the input moved, the mic track the
      // connect above raised is still bound to the device that was current
      // when it was created, so it has to be rebuilt rather than merely
      // resynced.
      if (await _applySavedAudioDevices()) {
        await _refreshMicrophoneCapture();
      } else {
        await _syncMicrophoneTransmission();
      }
      // Android evicts a backgrounded process; LiveKit does nothing about
      // that, so the call gets a foreground service to stand on. Its
      // notification is also the only part of the call still on screen once
      // the app is put away, so it is told what to say and what its buttons
      // do.
      unawaited(
        CallForegroundService.callStarted(
          channelName: _channelName(server.channels, channelId),
          serverName: server.name,
          micEnabled: state.isMicEnabled,
          onToggleMute: toggleMicrophone,
          onLeave: disconnect,
        ),
      );
      unawaited(SoundService.instance.playJoin());
      // Joining already deafened is a state nobody else can see unless it is
      // said — and rejoining while deafened is exactly what a reconnect does.
      unawaited(_publishSelfState());
      _syncParticipants();
      _applyStoredSettings();
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] room.connect() threw: $e');
      // A cached token the server refuses is most often one minted before the
      // voice credentials were replaced, and a freshly minted one gets straight
      // in — so that case is tried once more before anyone sees an error. The
      // second attempt has no cached token to reach for, so it cannot loop.
      // See [VoiceRejoin].
      final mintAgain = cached != null && VoiceRejoin.refusedCachedToken(e);
      if (!mintAgain) {
        emit(
          state.copyWith(
            connectionState: LiveKitConnectionState.error,
            failure: ConnectionFailure.from(e),
          ),
        );
      }
      // The key material, and the doorbell subscription [_prepareE2EE] may
      // have opened to ask for it, both belong to a call that is not
      // happening. Nothing used to be held this early, so nothing had to be
      // let go here.
      _clearE2EE();
      // Caught, because a room that never connected does not always report its
      // own disconnect, and `disconnect` then times out waiting for it. The
      // exception used to escape from here, past everything below: nobody saw
      // it while the error had already been shown, but it skipped the second
      // attempt and left "Connecting…" on screen for good.
      try {
        await room.disconnect();
        await room.dispose();
      } catch (e) {
        HelperMethods.printDebug('[LiveKit] teardown after a failed join: $e');
      }
      if (mintAgain) {
        _tokenCubit.invalidateToken(channelId);
        await connectToChannel(
          channelId: channelId,
          micEnabled: micEnabled,
          cameraEnabled: cameraEnabled,
        );
      }
    }
  }

  /// The channel's name for the notification. A plain loop rather than a
  /// lookup: this runs once per join, over a handful of channels.
  String _channelName(List<Channel> channels, String channelId) {
    for (final channel in channels) {
      if (channel.id == channelId) return channel.name;
    }
    return 'Voice';
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
}
