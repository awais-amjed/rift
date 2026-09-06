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
  ScreenshareCubit? get _screenshareCubit;
  List<EventsListener<RoomEvent>> get _listeners;
  Future<void> _stopVoiceActivityMonitor();

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

      unawaited(SoundService.instance.playLeave());
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
    } finally {
      _disconnecting = false;
    }
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
