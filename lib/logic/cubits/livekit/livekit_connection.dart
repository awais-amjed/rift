part of 'livekit_cubit.dart';

/// Over the cubit-part budget and one job: every step of a join depends on
/// the one before it, and splitting them would scatter a single sequence.
///
/// Joining and leaving a LiveKit room, and tearing the room down cleanly.
///
/// Connecting always cleans up any previous room first, and emits
/// `connecting` before it does — otherwise the disconnect event fired during
/// cleanup reads as an unexpected drop and clears the new channel.
mixin _LiveKitConnectionMixin on Cubit<LiveKitState>, _E2EEMixin {
  AppCubit get _appCubit;
  TokenCubit get _tokenCubit;
  VoiceApi? get _voiceApi;

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

  /// Implemented by [_DmCallConnectMixin].
  Future<void> rejoinDmCall();

  /// Implemented by the cubit. A share is a connection of its own, so a join
  /// has to take it along or end it — see [_followShares].
  ScreenshareCubit? get _screenshareCubit;
  SoundShareCubit? get _soundShareCubit;
  WatchResume get _watchResume;

  /// Both implemented by [_LiveKitLeaveMixin]. Joining needs them because a
  /// join that fails partway has to undo itself, and because being moved to
  /// another channel is a leave followed by a join.
  Future<void> disconnect();
  Future<void> _cleanupRoom();
  void forgetChannelToken(String? channelId);
  bool _shouldTransmitMic({bool? micEnabled});
  AudioCaptureOptions _buildAudioCaptureOptions();
  String? get _captureDeviceId;
  set _captureDeviceId(String? deviceId);

  /// Puts the user's saved input and output devices — or the system
  /// defaults, where none are saved — in force for this call, and reports
  /// whether the mic track has to be remade on a different input.
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
      final input = applied.input ?? _unresolvedDefault();
      if (input == _captureDeviceId) return false;
      _captureDeviceId = input;
      return true;
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] saved audio device refused: $e');
      return false;
    }
  }

  /// What the mic tracks should name when nothing was applied: nothing at
  /// all if the choice is "System default", so the plugin falls back to its
  /// first entry — WebRTC's default on Linux — rather than every track going
  /// on naming a device picked earlier in the session. Otherwise (a saved
  /// device that is gone or refused) whatever the tracks already name.
  String? _unresolvedDefault() =>
      _appCubit.state.inputDeviceId == null ? null : _captureDeviceId;

  /// Connects to a LiveKit channel. Server context is resolved internally via
  /// [_session]; callers only supply the channel and media preferences.
  Future<void> connectToChannel({
    required String channelId,
    bool? micEnabled,
    bool? cameraEnabled,
  }) async {
    final hadRoom = state.room != null;
    final wasConnecting =
        state.connectionState == LiveKitConnectionState.connecting;
    // The channel this switch is leaving, read before the emit below renames
    // it. Its token names a node and is dropped for the same reason leaving
    // drops one — see [forgetChannelToken].
    final leaving = state.currentChannelId;
    // The streams being watched, waited for through a rejoin of the same
    // call — a region change, or the connection giving out. Each sharer's
    // connection follows the call into the new room under the identity it
    // had, so the viewer goes on watching instead of being offered the
    // stream again.
    if (leaving == channelId) {
      _watchResume.remember(state.subscribedScreenshares, DateTime.now());
    }

    // Emit 'connecting' before cleanup so the RoomDisconnectedEvent fired during
    // _cleanupRoom is not misread as an unexpected disconnect and doesn't clear
    // the new channel ID.
    emit(
      state.copyWith(
        connectionState: LiveKitConnectionState.connecting,
        currentChannelId: channelId,
        clearDmCall: true,
        clearFailure: true,
      ),
    );

    if (hadRoom || wasConnecting) await _cleanupRoom();
    if (leaving != channelId) forgetChannelToken(leaving);

    emit(state.copyWith(clearRoom: true));

    final server = _session?.selectedServer;
    if (server == null) {
      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.error,
          failure: const ConnectionFailure.noServer(),
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
    // Where the mint said to take it. Null from a server too old to say, and
    // then the server row answers — see [CachedToken.livekitUrl].
    String? mintedUrl;
    final cached = _tokenCubit.getValidToken(
      server.supabaseUrl,
      channelId,
      userId,
    );
    if (cached != null) {
      livekitToken = cached.token;
      mintedUrl = cached.livekitUrl;
    } else {
      final response = await _voiceApi!.getChannelToken(channelId);
      if (!response.success) {
        HelperMethods.printDebug(
          '[LiveKit] Failed to get channel token: ${response.error}',
        );
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
      mintedUrl = response.data['livekit_url'] as String?;
      _tokenCubit.saveToken(
        server.supabaseUrl,
        channelId,
        userId,
        livekitToken,
        livekitUrl: mintedUrl,
      );
    }

    // The address the token was minted for, then the server's own. Checked
    // here rather than before the token, because the token is what names it:
    // a channel able to live on a different LiveKit than its server's default
    // has to be told so by the thing that decided it.
    final livekitUrl = mintedUrl ?? server.livekitUrl;
    if (livekitUrl == null) {
      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.error,
          failure: const ConnectionFailure.noLiveKitUrl(),
        ),
      );
      return;
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

    final mintAgain = await _joinRoom(
      livekitUrl: livekitUrl,
      livekitToken: livekitToken,
      e2ee: e2ee,
      micEnabled: micEnabled,
      cameraEnabled: cameraEnabled,
      tokenWasCached: cached != null,
      callName: _channelName(server.channels, channelId),
      serverName: server.name,
      // And from here on, a key rotated by somebody being removed has to
      // reach this call rather than waiting for a rejoin.
      onConnected: () => _watchKeyRotations(server, channelId),
    );
    if (mintAgain) {
      _tokenCubit.invalidateToken(channelId);
      await connectToChannel(
        channelId: channelId,
        micEnabled: micEnabled,
        cameraEnabled: cameraEnabled,
      );
    }
  }

  /// The half of a join that is the same whatever the call is: a room, keyed
  /// and connected, with the devices, the notification and the roster set up
  /// behind it. A channel and a DM call differ only in how they got here —
  /// which token, which address, which key.
  ///
  /// Answers whether the join should be tried once more with a freshly minted
  /// token, which is only ever true for a cached token the server refused. Any
  /// other failure has already been put in the state by the time this returns.
  Future<bool> _joinRoom({
    required String livekitUrl,
    required String livekitToken,
    required E2EEOptions e2ee,
    required bool? micEnabled,
    required bool? cameraEnabled,
    required bool tokenWasCached,
    required String callName,
    required String? serverName,
    void Function()? onConnected,
  }) async {
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
      // And every cryptor that already exists is pointed at the slot those
      // keys went into. The microphone is published by `FastConnectOptions`
      // *inside* the connect above, so its sender cryptor was built before
      // there was a key to index by and took slot 0 — while the key lands on
      // `version % 16`, which is slot 1 for an unrotated channel. Without
      // this the call comes up perfectly and nobody can hear you.
      //
      // Not the listener's job: `LocalTrackPublished` fires while
      // `state.room` is still null, so it has no room to ask. It covers every
      // publish after this one — unmuting, the camera, a track rebuilt when
      // the input device moved.
      await room.e2eeManager?.setKeyIndex(_callKeyIndex);
      onConnected?.call();

      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.connected,
          room: room,
          connectedAt: DateTime.now(),
          connectedLivekitUrl: livekitUrl,
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
      // Joined muted, the call plays at 16 kHz until the mic has run once —
      // see [PlayoutWarmup]. After the devices, so it opens the chosen one.
      if (_shouldTransmitMic()) {
        PlayoutWarmup.markDone();
      } else {
        unawaited(PlayoutWarmup.run(_buildAudioCaptureOptions()));
      }
      // Android evicts a backgrounded process; LiveKit does nothing about
      // that, so the call gets a foreground service to stand on. Its
      // notification is also the only part of the call still on screen once
      // the app is put away, so it is told what to say and what its buttons
      // do.
      unawaited(
        CallForegroundService.callStarted(
          channelName: callName,
          serverName: serverName,
          micEnabled: state.isMicEnabled,
          onToggleMute: toggleMicrophone,
          onLeave: disconnect,
        ),
      );
      unawaited(SoundService.instance.play(AppSound.presence));
      // Joining already deafened is a state nobody else can see unless it is
      // said — and rejoining while deafened is exactly what a reconnect does.
      unawaited(_publishSelfState());
      _syncParticipants();
      _applyStoredSettings();
      unawaited(_followShares());
      return false;
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] room.connect() threw: $e');
      // A cached token the server refuses is most often one minted before the
      // voice credentials were replaced, and a freshly minted one gets straight
      // in — so that case is tried once more before anyone sees an error. The
      // second attempt has no cached token to reach for, so it cannot loop.
      // See [VoiceRejoin].
      final mintAgain = tokenWasCached && VoiceRejoin.refusedCachedToken(e);
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
      return mintAgain;
    }
  }

  /// Takes this device's screen and sound shares into the call it is now in,
  /// or ends them if they were in another or the call is over. Each share is
  /// its own connection, so nothing about the call's own reconnect reaches
  /// it: after a region change or a rejoin it went on streaming into the room
  /// everybody had left. Run after every join, and whenever the call ends or
  /// changes (`LiveKitCubit.onChange`).
  Future<void> _followShares() async {
    await _screenshareCubit?.followCall();
    await _soundShareCubit?.followCall();
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
    if (state.dmCall != null) return rejoinDmCall();
    final channelId = state.currentChannelId;
    if (channelId == null) return;
    _tokenCubit.invalidateToken(channelId);
    await connectToChannel(channelId: channelId);
  }
}
