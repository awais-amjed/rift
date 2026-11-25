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
  VoiceApi? _voiceOn(String serverId);

  /// Implemented by the cubit and its other mixins.
  void _syncParticipants();
  EventsListener<RoomEvent> setupRoomListeners(Room room);
  List<EventsListener<RoomEvent>> get _listeners;

  /// Implemented by the cubit: see [CallSteps].
  CallSteps get _callSteps;
  void _forgetDmMediaKey();
  void _applyStoredSettings();
  bool _mutedHere(Room room, Participant participant, TrackPublication pub);
  bool _hearsAudio(
    Room room,
    Participant participant,
    TrackPublication publication,
  );
  void _applyVoicePrivacy([Room? room]);
  bool get _voiceRestricted;

  Future<void> _syncMicrophoneTransmission();

  /// Implemented by the cubit: tells the room what this client is doing that
  /// it cannot see for itself.
  Future<void> _publishSelfState();
  void _noticeClippers();

  /// See `_RustWatchMixin`: starts over with each room.
  set _rustWatchGaveOut(bool gaveOut);

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

  /// Implemented by [_RoomEventsMixin]: the streams watched again after a
  /// rejoin, which arrived before the room was in the state.
  void _receiveResumedPictures();

  /// Both implemented by [_LiveKitLeaveMixin]. Joining needs them because a
  /// join that fails partway has to undo itself, and because being moved to
  /// another channel is a leave followed by a join.
  Future<void> disconnect();
  Future<void> _cleanupRoom();
  bool _shouldTransmitMic({bool? micEnabled});
  // ignore: unused_element_parameter
  bool _shouldCaptureMic({bool? micEnabled});
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
        outputId: _appCubit.state.callOutputId,
        room: state.room,
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

  /// Whether the mic track the connect raised was made with other settings
  /// than are in force now.
  ///
  /// Its options were taken when the room was built, and a change while the
  /// call was connecting — a model's files landing, so the built-in
  /// suppressor goes off under it, or echo cancellation toggled — asked for
  /// a rebuild that found no connected room and was dropped. The track kept
  /// the old ones until the next mute or rejoin.
  bool _micMadeWithOldOptions() {
    final track = state.room?.localParticipant
        ?.getTrackPublicationBySource(TrackSource.microphone)
        ?.track;
    if (track is! LocalAudioTrack) return false;
    final made = track.currentOptions;
    final now = _buildAudioCaptureOptions();
    return made.noiseSuppression != now.noiseSuppression ||
        made.echoCancellation != now.echoCancellation ||
        made.autoGainControl != now.autoGainControl;
  }

  /// What the mic tracks should name when nothing was applied: nothing at
  /// all if the choice is "System default", so the plugin falls back to its
  /// first entry — WebRTC's default on Linux — rather than every track going
  /// on naming a device picked earlier in the session. Otherwise (a saved
  /// device refused, or gone with no default to stand in) whatever the
  /// tracks already name.
  String? _unresolvedDefault() =>
      _appCubit.state.inputDeviceId == null ? null : _captureDeviceId;

  /// Connects to a LiveKit channel on [serverId] — named by a rejoin of the
  /// call already running — or else the server that lists the channel.
  ///
  /// Never simply the selected server, which is only where the person is
  /// looking. A call that drops and rejoins, or a moderator moving somebody,
  /// happens while they read another server, and a join that asked that one
  /// got no token and stayed out.
  Future<void> connectToChannel({
    required String channelId,
    required String serverId,
    bool? micEnabled,
    bool? cameraEnabled,
  }) async {
    ViewerCodecs.askEarly();
    final turn = _callSteps.begin();
    final hadCall =
        state.room != null ||
        state.connectionState == LiveKitConnectionState.connecting;

    // The channel this switch is leaving, read before the emit below renames
    // it.
    final leaving = state.currentChannelId;
    // The streams being watched, waited for through a rejoin of the same
    // call — a region change, or the connection giving out. Each sharer's
    // connection follows the call into the new room under the identity it
    // had, so the viewer goes on watching instead of being offered the
    // stream again.
    if (leaving == channelId) {
      _watchResume.remember(state.subscribedScreenshares, DateTime.now());
    } else {
      // Another channel's people, drawn under this one's name until it
      // connects.
      _appCubit.setParticipants([]);
    }

    // Emit 'connecting' before cleanup so the RoomDisconnectedEvent fired during
    // _cleanupRoom is not misread as an unexpected disconnect and doesn't clear
    // the new channel ID.
    emit(
      state.copyWith(
        connectionState: LiveKitConnectionState.connecting,
        currentChannelId: channelId,
        // The server asked for, even one this device no longer has: the join
        // fails below, and Retry asks the same server again.
        currentServerId: serverId,
        // What the call joins with, said now: a mute pressed while it
        // connects changes this, and the connect honours it.
        isMicEnabled: micEnabled,
        isCameraEnabled: cameraEnabled,
        participants: leaving == channelId ? null : const [],
        clearDmCall: true,
        clearFailure: true,
      ),
    );

    await _callSteps.run(
      () => _joinChannel(
        turn,
        channelId: channelId,
        serverId: serverId,
        cleanUp: hadCall,
      ),
    );
  }

  /// The part of [connectToChannel] that waits, run in [turn] once whatever
  /// was pressed before it has finished ([CallSteps]). A press after it
  /// makes it stale, and it stops at the next wait without a word: whatever
  /// was pressed has its own say.
  Future<void> _joinChannel(
    int turn, {
    required String channelId,
    required String serverId,
    required bool cleanUp,
  }) async {
    bool current() => _callSteps.isCurrent(turn);
    if (!current()) return;

    if (cleanUp || state.room != null) await _cleanupRoom();
    // A DM call's key goes with the call, here as on a full leave: switched
    // to a channel, it stayed in memory until the next one.
    _forgetDmMediaKey();
    if (!current()) return;

    emit(state.copyWith(clearRoom: true));

    final server = _session?.serverById(serverId);
    if (server == null || server.user == null) {
      _failJoin(const ConnectionFailure.noServer());
      return;
    }

    try {
      // Every join mints its own token, and is told by the mint which LiveKit
      // the call is on. A token kept from an earlier join named the node the
      // call was on then: the call could since have ended and started again
      // on another node, or moved, and a client reusing it opened a second
      // room of the same name there and sat in it alone. It could also carry
      // a grant the member has since lost, which `livekit_webhook` takes back
      // only on a node whose webhook reaches this server.
      //
      // The token and the key at once, since neither needs the other: asked
      // for one after the other, each added a round trip to the wait for the
      // room. Both are waited for before either answer counts, so that a
      // token refused leaves nothing of the key still on its way.
      //
      // The key before the room. A call joined without one would connect,
      // work, and be readable by the server — the single thing this is here
      // to stop — so there is no unencrypted fallback path to take by
      // accident.
      final (response, e2ee) = await (
        _voiceOn(server.id)!.getChannelToken(channelId),
        _prepareE2EE(channelId, server),
      ).wait;
      if (!current()) {
        _clearE2EE();
        return;
      }

      if (!response.success) {
        HelperMethods.printDebug(
          '[LiveKit] Failed to get channel token: ${response.error}',
        );
        _clearE2EE();
        _failJoin(ConnectionFailure.tokenRefused(response));
        return;
      }
      final livekitToken = response.data['token'] as String;

      // The address the token was minted for, then the server's own: null
      // from a server too old to say. Checked here rather than before the
      // token, because the token is what names it: a channel able to live on
      // a different LiveKit than its server's default has to be told so by
      // the thing that decided it.
      final livekitUrl =
          response.data['livekit_url'] as String? ?? server.livekitUrl;
      if (livekitUrl == null) {
        _clearE2EE();
        _failJoin(const ConnectionFailure.noLiveKitUrl());
        return;
      }

      final (:options, :refused) = e2ee;
      if (options == null) {
        _failJoin(refused ?? const ConnectionFailure.noChannelKey());
        return;
      }

      await _joinRoom(
        livekitUrl: livekitUrl,
        livekitToken: livekitToken,
        e2ee: options,
        callName: _channelName(server.channels, channelId),
        serverName: server.name,
        isCurrent: current,
        // And from here on, a key rotated by somebody being removed has to
        // reach this call rather than waiting for a rejoin.
        onConnected: () => _watchKeyRotations(server, channelId),
      );
    } catch (e) {
      // Thrown before the room: the vault, the key provider, an answer
      // without a token. Uncaught, it left "Connecting…" up for good.
      HelperMethods.printDebug('[LiveKit] join gave out before the room: $e');
      _clearE2EE();
      if (current()) _failJoin(ConnectionFailure.from(e));
    }
  }

  /// A join that will not happen, said in the state. The people it showed
  /// belong to a call this device is not in.
  void _failJoin(ConnectionFailure failure) {
    _appCubit.setParticipants([]);
    emit(
      state.copyWith(
        connectionState: LiveKitConnectionState.error,
        failure: failure,
        participants: const [],
      ),
    );
  }

  /// The half of a join that is the same whatever the call is: a room, keyed
  /// and connected, with the devices, the notification and the roster set up
  /// behind it. A channel and a DM call differ only in how they got here —
  /// which token, which address, which key. A failure is in the state by the
  /// time this returns.
  Future<void> _joinRoom({
    required String livekitUrl,
    required String livekitToken,
    required E2EEOptions e2ee,
    required String callName,
    required String? serverName,
    required bool Function() isCurrent,
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
    // Off from the start: the event comes too late to keep a held share's
    // sound from playing as somebody joins (CALLS.md). Somebody you muted as
    // well, who was heard until the join had finished.
    room.audioHeldOnArrival = (participant, publication) =>
        !_hearsAudio(room, participant, publication) ||
        _mutedHere(room, participant, publication);
    final listener = setupRoomListeners(room);

    try {
      // As the state has them now, which a press while connecting changed.
      final useMicEnabled = state.isMicEnabled;
      final useCameraEnabled = state.isCameraEnabled;
      // With anybody's ears shut to you, the mic waits until the server has
      // been told who may receive it: published inside the connect, it would
      // reach everyone present before the list could be sent ([VoicePrivacy]).
      // The sync further down turns it on.
      final joinMicEnabled =
          !_voiceRestricted && _shouldTransmitMic(micEnabled: useMicEnabled);

      await room.connect(
        livekitUrl,
        livekitToken,
        fastConnectOptions: FastConnectOptions(
          microphone: TrackOption(enabled: joinMicEnabled),
          camera: TrackOption(enabled: useCameraEnabled),
        ),
      );
      // Muted or deafened while that connected: the mic went out live, and
      // stayed live until the devices further down were applied.
      if (joinMicEnabled && !_shouldTransmitMic()) {
        await room.localParticipant?.setMicrophoneEnabled(false);
      }

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
      // Left, or somewhere else pressed, while this connected.
      if (!isCurrent()) {
        _clearE2EE();
        await _dropUnjoinedRoom(room, listener);
        return;
      }
      _applyVoicePrivacy(room);
      onConnected?.call();

      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.connected,
          room: room,
          connectedAt: SteadyClock.now(),
          connectedLivekitUrl: livekitUrl,
          arrivals: state.arrivals + 1,
        ),
      );
      // Saved mutes and volumes on whoever is here, now there is a room to
      // find them in: their tracks arrived while there was none.
      _applyStoredSettings();

      // Only now can the saved devices be applied — see
      // [_applySavedAudioDevices]. If the input moved, the mic track the
      // connect above raised is still bound to the device that was current
      // when it was created, so it has to be rebuilt rather than merely
      // resynced.
      if (await _applySavedAudioDevices() || _micMadeWithOldOptions()) {
        await _refreshMicrophoneCapture();
      } else {
        await _syncMicrophoneTransmission();
      }
      // Joined muted, the call plays at 16 kHz until the mic has run once —
      // see [PlayoutWarmup]. After the devices, so it opens the chosen one.
      // Push-to-talk with the key up already runs it, sending silence.
      if (_shouldTransmitMic() ||
          (_shouldCaptureMic() && NoiseFilter.canSilence)) {
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
          micEnabled: state.isMicOn,
          onToggleMute: toggleMicrophone,
          onLeave: disconnect,
        ),
      );
      unawaited(SoundService.instance.play(AppSound.presence));
      // Joining already deafened is a state nobody else can see unless it is
      // said — and rejoining while deafened is exactly what a reconnect does.
      _rustWatchGaveOut = false;
      unawaited(_publishSelfState());
      _syncParticipants();
      _applyStoredSettings();
      _receiveResumedPictures();
      unawaited(_followShares());
      // Those already here with clipping on, said once for the call.
      _noticeClippers();
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] room.connect() threw: $e');
      // A join nobody is waiting for any more fails without a word.
      if (isCurrent()) _failJoin(ConnectionFailure.from(e));
      // The key material, and the doorbell subscription [_prepareE2EE] may
      // have opened to ask for it, both belong to a call that is not
      // happening. Nothing used to be held this early, so nothing had to be
      // let go here.
      _clearE2EE();
      await _dropUnjoinedRoom(room, listener);
    }
  }

  /// Takes down a room that never became the call's: a join that failed, or
  /// one overtaken while it connected. Its listener goes first, so its own
  /// disconnect is not heard as the call dropping, and because nothing else
  /// holds it: the next teardown only finds the listeners of a room in the
  /// state.
  Future<void> _dropUnjoinedRoom(
    Room room,
    EventsListener<RoomEvent> listener,
  ) async {
    _listeners.remove(listener);
    try {
      await listener.dispose();
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] listener of an unjoined room: $e');
    }
    // Caught, because a room that never connected does not always report its
    // own disconnect, and `disconnect` then times out waiting for it. The
    // exception used to escape a failed join here, skipping the second attempt
    // and leaving "Connecting…" on screen for good.
    //
    // Disposed whatever the disconnect did. A disconnect that timed out used
    // to skip the dispose with it, and the half-joined room went on holding
    // its tracks and native observers into the next call.
    try {
      await room.disconnect();
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] teardown of an unjoined room: $e');
    }
    try {
      await room.dispose();
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] dispose of an unjoined room: $e');
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

  /// Runs the failed join again, against the channel that failed, with a
  /// token of its own like any join.
  Future<void> retryConnection() async {
    if (state.dmCall != null) return rejoinDmCall();
    final channelId = state.currentChannelId;
    final serverId = state.currentServerId;
    if (channelId == null || serverId == null) return;
    await connectToChannel(channelId: channelId, serverId: serverId);
  }
}
