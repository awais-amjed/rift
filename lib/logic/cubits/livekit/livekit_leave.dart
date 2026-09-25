part of 'livekit_cubit.dart';

/// Leaving a call, and taking everything down with it.
///
/// Split from joining because the two have opposite failure modes. A failed
/// join is reported to the person who pressed the button and can be retried; a
/// failed teardown leaves a room object, a listener and a key behind, and the
/// next join inherits them. That is why almost everything here is
/// unconditional and nothing here is retried.
mixin _LiveKitLeaveMixin on Cubit<LiveKitState>, _E2EEMixin {
  /// Guards [disconnect] against re-entering itself — see its doc comment.
  bool get _disconnecting;
  set _disconnecting(bool value);

  /// Implemented by the cubit and its other mixins.
  AppCubit get _appCubit;
  TokenCubit get _tokenCubit;
  ScreenshareCubit? get _screenshareCubit;
  SoundShareCubit? get _soundShareCubit;
  SoundboardCubit? get _soundboardCubit;
  List<EventsListener<RoomEvent>> get _listeners;
  Future<void> _stopVoiceActivityMonitor();

  /// Disconnects from the current room.
  ///
  /// Runs at most once at a time. Clearing the selected channel below is the
  /// same signal `VoiceConnectionListener` listens on to leave a call, so this re-enters
  /// itself on every leave: the second call starts as soon as the first
  /// awaits, and both then tear down the same [Room].
  Future<void> disconnect() async {
    if (_disconnecting) return;
    _disconnecting = true;
    // Read before anything clears it; the token is dropped at the end.
    final leaving = state.currentChannelId;
    try {
      if (_screenshareCubit?.state.isSharing == true) {
        await _screenshareCubit?.stopScreenShare();
      }
      // Same for a shared track: its connection outlives the call otherwise,
      // playing to a room the sharer has left.
      if (_soundShareCubit?.state.isSharing == true) {
        await _soundShareCubit?.stopSoundShare();
      }

      // A clip is played locally, so nothing about leaving the room stops
      // one that is halfway through — it would go on sounding in an empty
      // window. Not awaited: the leave should not wait on an airhorn.
      unawaited(_soundboardCubit?.silence() ?? Future<void>.value());

      unawaited(SoundService.instance.play(AppSound.presence, ending: true));
      _appCubit.setParticipants([]);
      _appCubit.setSelectedChannelId(null);

      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.disconnected,
          clearChannelId: true,
          clearFailure: true,
          participants: [],
        ),
      );

      await _cleanupRoom();
      // The call's key ring goes with the call. Holding it would leave the
      // last channel's key in memory long after leaving, and would key the
      // next call with it if a load ever failed quietly.
      _clearE2EE();
      _keyring?.clear();
      emit(state.copyWith(clearRoom: true));
      forgetChannelToken(leaving);
    } finally {
      _disconnecting = false;
    }
  }

  /// Drops the cached token for a channel this device has just left.
  ///
  /// **A cached token names a node, and nothing tells the client when that
  /// stops being where the call is.** The token is reusable for 55 minutes;
  /// the row saying where the call lives is released as soon as the room is
  /// empty. Rejoin in between and the client goes straight to the node its
  /// token names, without asking — so nothing records where it went, and the
  /// next person to join is sent wherever the channel's pin or their own
  /// measurement says. Two people, one channel, two rooms of the same name on
  /// two boxes, each alone.
  ///
  /// So the token is dropped whenever its call ends here. It costs one edge
  /// call per join, which is what a first join costs anyway, and it makes the
  /// mint the only thing that decides where a call is — which is the rule the
  /// claim exists to enforce.
  void forgetChannelToken(String? channelId) {
    if (channelId != null) _tokenCubit.invalidateToken(channelId);
  }

  Future<void> _cleanupRoom() async {
    // Nothing left to hold the process up for. Unconditional: this is the one
    // path every teardown goes through, and a notification for a call that
    // has ended is worse than one that is a moment late.
    unawaited(CallForegroundService.callEnded());

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
          await l.dispose();
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
