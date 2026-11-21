part of 'screenshare_cubit.dart';

/// A share staying with its call: moved into the call's new room when the
/// call reconnects or changes region, and ended when the call it belongs to
/// is over.
mixin _ScreenshareFollowMixin on Cubit<ScreenshareState> {
  LiveKitCubit? get _livekitCubit;

  Future<void> stopScreenShare();

  /// Keeps this device's share with its call, which has just connected.
  ///
  /// A region change and a rejoin after the connection gave out both put the
  /// call in a new room, and the share is a connection of its own that none
  /// of that touched — it went on streaming into the room everybody had left.
  /// On a desktop it is moved after them, capture and all, so a Wayland
  /// portal is not asked again. Where the SDK shares the screen the share was
  /// a track on the old room and went with it; a browser starts a share only
  /// from a click, and Android only with fresh consent, so the sharer is told
  /// to start it again.
  ///
  /// A share in any other call ends: it belongs to the call it was started
  /// in. So does one whose call failed to come back, or it streams on to a
  /// room the sharer is not in.
  Future<void> followCall() async {
    final livekit = _livekitCubit;
    if (livekit == null) return;
    if (state.isConnecting) return _stopStartIfCallGone();
    if (!state.isSharing) return;
    final gone = _callGone(state.channelId);
    if (ScreenshareCubit._sdkCapturesScreen) {
      return _forgetSdkShare(tell: !gone);
    }
    if (gone) return stopScreenShare();
    // Joining the same call again, which may yet fail: whichever way it
    // ends brings this back here.
    if (livekit.state.connectionState != LiveKitConnectionState.connected) {
      return;
    }

    final response = await livekit.shareToken(screenShare: true);
    // Stopped by the sharer while the token came: nothing left to move, and
    // nothing to say about it.
    if (!state.isSharing) return;
    final livekitUrl =
        response.data?['livekit_url'] as String? ??
        livekit.callServer?.livekitUrl;
    final encryption = livekit.callEncryption;
    if (!response.success || livekitUrl == null || encryption == null) {
      return _endUnmoved(response.error ?? 'the call is not ready');
    }
    try {
      await moveScreenshare(
        room: ShareRoom(
          livekitUrl: livekitUrl,
          livekitToken: response.data['token'] as String,
          e2EeKey: encryption.key,
          e2EeKeyIndex: encryption.index,
        ),
      );
    } catch (e) {
      await _endUnmoved('$e');
    }
  }

  /// A desktop share still starting when its call was left. Under Wayland
  /// the desktop's picker waits on the person for up to ten minutes, with
  /// the share's connection already in the room, and a window picked after
  /// leaving went out into the call that was left before anything ended it.
  /// Rust's start hears a stop while it waits for the first picture, and
  /// gives up ([ScreenshareCubit.startScreenShare] says nothing about it).
  /// A start that has not reached Rust yet looks for itself before it does.
  Future<void> _stopStartIfCallGone() async {
    if (ScreenshareCubit._sdkCapturesScreen || !_callGone(_startingFor)) {
      return;
    }
    await stopScreenshare();
  }

  /// The call the share now starting is for.
  String? _startingFor;

  /// Whether the call [channelId] names is over for this device — it is in
  /// another call or none, or its join failed — so a share of it must not
  /// go on.
  bool _callGone(String? channelId) {
    final call = _livekitCubit?.state;
    return call == null || call.callKey != channelId || call.isCallOver;
  }

  /// Ends a share that has just come up for a call that ended while it was
  /// starting — the capture, the token and the connect take seconds, and
  /// nothing else is listening for that call any more.
  Future<void> _endIfCallGone(String channelId) async {
    if (!state.isSharing) return;
    if (!_callGone(channelId)) return _followIfRoomChanged();
    if (ScreenshareCubit._sdkCapturesScreen) {
      // A phone's consent sheet is up for as long as the person leaves it,
      // and the share goes into whatever room is the call's when they
      // agree: another call's, after a move or an answered DM call. Taken
      // out of there too, or it streamed on under an unlit button.
      await _livekitCubit?.stopSdkScreenShare();
      return _forgetSdkShare(tell: false);
    }
    await stopScreenShare();
  }

  /// The room the call was in when the share now coming up began, read at
  /// its start. A region change or a rejoin in between moved the call while
  /// the share was not yet up to follow it, so it came up in the room
  /// everybody had left.
  Room? _startedInRoom;

  Future<void> _followIfRoomChanged() async {
    final startedIn = _startedInRoom;
    _startedInRoom = null;
    if (startedIn == null || ScreenshareCubit._sdkCapturesScreen) return;
    if (identical(startedIn, _livekitCubit?.state.room)) return;
    // Still joining: the join's end brings [followCall] round itself.
    await followCall();
  }

  /// A share that could not follow its call: stop it rather than leave it
  /// streaming to a room nobody is in, and say why the stream ended.
  Future<void> _endUnmoved(String reason) async {
    HelperMethods.printDebug(
      '✗ Screen share could not follow the call: $reason',
    );
    await stopScreenShare();
    emit(
      state.copyWith(
        notice: Notice.error(
          'Your stream stopped when the call reconnected. Share again to '
          'carry on.',
          duration: Notice.long,
        ),
      ),
    );
  }

  /// The SDK's share ended without Rift asking: the browser's own Stop
  /// sharing button, or Android taking the capture back. Nothing is left to
  /// stop, so only the state is put back. A stop of Rift's own has the share
  /// `stopping` already, and is left to finish.
  Future<void> sdkShareEnded() async {
    if (!ScreenshareCubit._sdkCapturesScreen ||
        state.status != ScreenshareStatus.sharing) {
      return;
    }
    await _forgetSdkShare(tell: false);
  }

  /// The SDK's share went with the room it was published in, so there is
  /// nothing to stop — [stopScreenShare] would toggle the new room's share
  /// *on*. Only the state and the foreground service are put back.
  Future<void> _forgetSdkShare({required bool tell}) async {
    await CallForegroundService.screenShareStopped();
    emit(
      state.copyWith(
        status: ScreenshareStatus.idle,
        clearChannelId: true,
        clearSettings: true,
        clearError: true,
      ),
    );
    if (tell) {
      emit(
        state.copyWith(
          notice: Notice.info(
            'Your stream stopped',
            'The call reconnected. Share again to carry on.',
          ),
        ),
      );
    }
  }
}
