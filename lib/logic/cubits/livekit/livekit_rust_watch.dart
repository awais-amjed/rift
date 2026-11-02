part of 'livekit_cubit.dart';

/// Watched shares' pictures through the Rust watch connection, drawn by the
/// runner on the GPU, instead of through this room ([RustWatch] says why).
///
/// One watch connection per call, opened with the first share watched this
/// way and closed with the last. A share goes this way when it can, and the
/// way it always has otherwise:
/// - a build without stream textures, or `RIFT_WATCH_PATH=call`;
/// - a server that does not mint watch connections (its answer names the
///   voice identity instead, and joining with that would kick this device's
///   own voice connection out of the call);
/// - anything failing, before or after it opens. That ends it for the rest
///   of the call, once, with a line in the log: the shares it held go back to
///   this room, and so does every share watched after.
///
/// The share's sound still comes through this room for now.
mixin _RustWatchMixin
    on Cubit<LiveKitState>, _E2EEMixin, _ScreenshareMixin, _RoomEventsMixin {
  Future<APIResponse> shareToken({
    bool screenShare = false,
    bool soundShare = false,
    bool watch = false,
  });

  /// The room the watch connection was opened beside, and the opening, which
  /// two shares watched together wait on as one. Null while none is open.
  Room? _rustWatchRoom;
  Future<bool>? _rustWatchOpening;

  /// The Rust path failed during this call, which watches as before from
  /// then on. Cleared when the call's room goes.
  bool _rustWatchFailed = false;

  StreamSubscription<WatchEvent>? _rustWatchEvents;

  /// Shares on their way to being watched through Rust, by identity.
  final Map<String, Future<bool>> _rustWatchPending = {};

  /// Receives [identity]'s picture through the watch connection; false when
  /// it cannot, and the caller subscribes in this room instead. Answers at
  /// once for a share it already holds.
  @override
  Future<bool> _watchThroughRust(String identity) {
    if (!RustWatch.available || _rustWatchFailed) return Future.value(false);
    if (state.watchedPictures.containsKey(identity)) return Future.value(true);
    // One at a time per share: Watch pressed and the share published can
    // both ask, and a second texture would replace the first in Rust.
    return _rustWatchPending[identity] ??= _beginRustWatch(
      identity,
    ).whenComplete(() => _rustWatchPending.remove(identity));
  }

  Future<bool> _beginRustWatch(String identity) async {
    final room = state.room;
    if (room == null) return false;
    // Your own phone's stream is a local track: nothing to receive.
    if (identity == room.localParticipant?.identity) return false;

    if (!await _openRustWatch(room)) return false;
    if (_rustWatchRoom != room) return false;

    final textureId = await RustWatch.watch(identity);
    if (textureId == null) {
      await _fallBackFromRust('no texture for $identity');
      return false;
    }
    // Stopped watching, or the call moved on, while the texture was made.
    if (_rustWatchRoom != room ||
        !state.subscribedScreenshares.contains(identity)) {
      await RustWatch.unwatch(identity, textureId);
      return false;
    }
    emit(
      state.copyWith(
        watchedPictures: {
          ...state.watchedPictures,
          identity: WatchedPicture(textureId: textureId),
        },
      ),
    );
    // Not received twice: the room subscribes by itself to what is
    // published, and may have done so before this was ready.
    final participant = room.remoteParticipants[identity];
    for (final pub in participant?.videoTrackPublications ?? const []) {
      if (pub.source == TrackSource.screenShareVideo && pub.subscribed) {
        unawaited(pub.unsubscribe());
      }
    }
    HelperMethods.printDebug('[LiveKit] watching $identity through Rust');
    return true;
  }

  /// Stops receiving [identity]'s picture through the watch connection, and
  /// closes the connection when it was the last. False when it held nothing.
  @override
  Future<bool> _unwatchThroughRust(String identity) async {
    final picture = state.watchedPictures[identity];
    if (picture == null) return false;
    emit(
      state.copyWith(
        watchedPictures: Map.of(state.watchedPictures)..remove(identity),
      ),
    );
    await RustWatch.unwatch(identity, picture.textureId);
    // Not while another is on its way: it is about to use the connection.
    if (state.watchedPictures.isEmpty &&
        _rustWatchPending.isEmpty &&
        _rustWatchRoom != null) {
      _rustWatchRoom = null;
      _rustWatchOpening = null;
      await RustWatch.stop();
    }
    return true;
  }

  /// Lets go of every picture held for a share no longer watched — a sharer
  /// who left, or Stop watching with a share already gone.
  @override
  void _letGoOfUnwatchedPictures() {
    for (final identity in state.watchedPictures.keys.toList()) {
      if (!state.subscribedScreenshares.contains(identity)) {
        unawaited(_unwatchThroughRust(identity));
      }
    }
  }

  Future<bool> _openRustWatch(Room room) {
    if (_rustWatchRoom == room) {
      return _rustWatchOpening ?? Future.value(true);
    }
    _rustWatchRoom = room;
    return _rustWatchOpening = _startRustWatch(room);
  }

  Future<bool> _startRustWatch(Room room) async {
    final encryption = callEncryption;
    if (encryption == null) return _rustWatchRefused('no call key');
    final response = await shareToken(watch: true);
    if (_rustWatchRoom != room) return false;
    final data = response.data;
    final token = data is Map ? data['token'] : null;
    final url = data is Map ? data['livekit_url'] : null;
    final identity = data is Map ? data['identity'] : null;
    if (!response.success || token is! String || url is! String) {
      return _rustWatchRefused(response.error ?? 'no token');
    }
    if (identity is! String || !ParticipantIdentity.isWatch(identity)) {
      return _rustWatchRefused('the server does not mint watch connections');
    }

    _rustWatchEvents ??= RustWatch.events.listen(_onRustWatchEvent);
    final error = await RustWatch.start(
      url: url,
      token: token,
      key: encryption.key,
      keyIndex: encryption.index,
    );
    if (error != null) return _rustWatchRefused(error);
    if (_rustWatchRoom != room) {
      await RustWatch.stop();
      return false;
    }
    return true;
  }

  bool _rustWatchRefused(String why) {
    HelperMethods.printDebug(
      '[LiveKit] watching through the call instead of Rust: $why',
    );
    _rustWatchFailed = true;
    _rustWatchRoom = null;
    _rustWatchOpening = null;
    return false;
  }

  void _onRustWatchEvent(WatchEvent event) {
    switch (event.kind) {
      case WatchEventKind.pictureSize:
        final picture = state.watchedPictures[event.shareIdentity];
        if (picture == null) return;
        emit(
          state.copyWith(
            watchedPictures: {
              ...state.watchedPictures,
              event.shareIdentity: picture.sized(event.width, event.height),
            },
          ),
        );
      case WatchEventKind.lost:
        if (_rustWatchRoom == null) return;
        unawaited(_fallBackFromRust('connection lost: ${event.reason}'));
    }
  }

  /// The Rust path gave out mid-call: the shares it held go back to this
  /// room, and the rest of the call watches that way.
  Future<void> _fallBackFromRust(String why) async {
    final held = state.watchedPictures.keys.toList();
    await _endRustWatch();
    _rustWatchRefused(why);
    final room = state.room;
    if (room == null) return;
    for (final identity in held) {
      if (!state.subscribedScreenshares.contains(identity)) continue;
      final participant = room.remoteParticipants[identity];
      for (final pub in participant?.videoTrackPublications ?? const []) {
        if (pub.source != TrackSource.screenShareVideo) continue;
        try {
          await pub.subscribe();
          await pub.setVideoQuality(VideoQuality.HIGH);
        } catch (e) {
          HelperMethods.printDebug(
            '[LiveKit] back to the call for $identity: $e',
          );
        }
      }
    }
    _syncParticipants();
  }

  /// Closes the watch connection and lets go of its textures — the call's
  /// room going, for whatever reason. The next room may try Rust again.
  @override
  Future<void> _endRustWatch() async {
    _rustWatchFailed = false;
    final textures = state.watchedPictures.values
        .map((p) => p.textureId)
        .toList();
    final wasOpen = _rustWatchRoom != null || textures.isNotEmpty;
    _rustWatchRoom = null;
    _rustWatchOpening = null;
    if (!wasOpen) return;
    if (state.watchedPictures.isNotEmpty) {
      emit(state.copyWith(watchedPictures: const {}));
    }
    // Stopped first: once it returns, nothing marks the textures.
    await RustWatch.stop();
    await RustWatch.disposeAll(textures);
  }

  /// The call moved to a new key version; shares started after it are
  /// sealed under it.
  @override
  void _rustWatchKeyMoved() {
    final encryption = callEncryption;
    if (_rustWatchRoom == null || encryption == null) return;
    unawaited(RustWatch.addKey(encryption.key, encryption.index));
  }

  Future<void> _closeRustWatchEvents() async {
    await _rustWatchEvents?.cancel();
    _rustWatchEvents = null;
  }
}
