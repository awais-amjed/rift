part of 'soundboard_cubit.dart';

/// The server's clips: reading them, adding, renaming and removing one, and
/// deleting the local copy of any that vanished.
///
/// Nothing here plays a sound or knows a call exists — the other half of the
/// cubit is the one listening on the data channel.
mixin _SoundboardLibraryMixin on Cubit<SoundboardState> {
  SoundboardApi _apiOn(String serverId);

  /// Whose library this is: the watched server.
  String? get _libraryServerId;

  /// That server's library calls, or null with none watched.
  SoundboardApi? get _library => switch (_libraryServerId) {
    final serverId? => _apiOn(serverId),
    null => null,
  };

  /// Counts reads, so one that comes back after a later one is dropped: a
  /// slow read from before a change brought a removed clip back, or took away
  /// one just added (and its file with it).
  int _reads = 0;

  /// A read that failed tries again once by itself after [_retryAfter]: the
  /// call's button is hidden over an empty library, so with nothing to press
  /// there is nothing that would otherwise ask again until the next change.
  Timer? _retryTimer;
  static const Duration _retryAfter = Duration(seconds: 30);

  /// [first] is the library's first read on its server, which may share one
  /// `server_start` with the server's other features opening.
  Future<void> refresh({bool first = false}) async {
    final serverId = _libraryServerId;
    if (serverId == null) return;
    _retryTimer?.cancel();
    final read = ++_reads;

    final api = _apiOn(serverId);
    final result = await api.listSounds(first: first);
    // The rail moved while this was in flight; the answer is another
    // server's and drawing it under this one's name would be a lie.
    if (isClosed || _libraryServerId != serverId) return;
    if (read != _reads) return;

    if (result.error != null) {
      // The clips already shown stay: a failed read is not an empty board,
      // and drawing it as one hid the button and said "Nothing here yet".
      emit(
        state.copyWith(
          status: SoundboardStatus.error,
          serverId: serverId,
          error: result.error,
        ),
      );
      _retryTimer = Timer(_retryAfter, () {
        if (!isClosed && _libraryServerId == serverId) unawaited(refresh());
      });
      return;
    }

    _forgetVanished(
      serverId: serverId,
      origin: api.origin,
      sounds: result.sounds,
    );

    emit(
      state.copyWith(
        status: SoundboardStatus.ready,
        serverId: serverId,
        sounds: result.sounds,
        clearError: true,
      ),
    );
  }

  /// Delete the files of clips that are no longer in the library.
  ///
  /// This is the only moment a client that did not do the deleting learns
  /// that a clip is gone: the row vanishes from the list it just read.
  /// Without this the picker was right everywhere and the disk was right
  /// only on the device that pressed Remove, leaving everybody else holding
  /// bytes nothing could name until the 30-day sweep — up to
  /// `SoundboardRepository.maxBytes` each, which stopped being negligible
  /// when a clip could be 5 MB.
  ///
  /// Two things it must not do, both of which would delete a whole server's
  /// clips at once:
  ///
  /// - act on a **failed** read. A refresh that could not reach the server
  ///   comes back with an empty list and an error, which is indistinguishable
  ///   from a library somebody emptied unless the error is checked —
  ///   [refresh] only calls this with a read that worked.
  /// - act across a **server switch**. `onServerChanged` resets the state
  ///   before the new server's first refresh, so the list being compared has
  ///   to be one that belonged to this same server.
  ///
  /// Which leaves one case it cannot reach, and should not try to: a device
  /// that was closed, or on another server, when the clip was deleted has no
  /// list to diff against and never learns. There is nothing to compare, so
  /// the 30-day sweep in [SoundboardCache] stays the backstop rather than
  /// this being made cleverer.
  void _forgetVanished({
    required String serverId,
    required String? origin,
    required List<SoundboardSound> sounds,
  }) {
    if (origin == null || state.serverId != serverId) return;
    if (state.sounds.isEmpty) return;

    final kept = {for (final sound in sounds) sound.objectPath};
    for (final sound in state.sounds) {
      if (kept.contains(sound.objectPath)) continue;
      unawaited(SoundboardCache.instance.forget(origin, sound.objectPath));
    }
  }

  /// Add a clip. Returns the reason it did not work, or null.
  Future<String?> add({
    required String name,
    String? emoji,
    required Uint8List bytes,
    required String contentType,
    required Duration duration,
  }) async {
    final library = _library;
    if (library == null) return ServerSession.gone;
    final result = await library.addSound(
      name: name,
      emoji: emoji,
      bytes: bytes,
      contentType: contentType,
      duration: duration,
    );
    if (result.error != null) return result.error;
    // A read already in flight began before this clip existed.
    _reads++;
    // Shown at once rather than waited for: the realtime doorbell will bring
    // the same row along in a moment, and a picker that stays empty until it
    // does reads as a failed upload.
    if (!isClosed && result.sound != null) {
      emit(state.copyWith(sounds: [...state.sounds, result.sound!]));
    }
    return null;
  }

  Future<String?> rename({
    required SoundboardSound sound,
    required String name,
    String? emoji,
  }) async {
    final library = _library;
    if (library == null) return ServerSession.gone;
    final result = await library.renameSound(
      soundId: sound.id,
      name: name,
      emoji: emoji,
    );
    if (!result.success) return result.error;
    _reads++;
    if (!isClosed) {
      emit(
        state.copyWith(
          sounds: [
            for (final s in state.sounds)
              if (s.id == sound.id)
                s.copyWith(name: name, emoji: emoji, clearEmoji: emoji == null)
              else
                s,
          ],
        ),
      );
    }
    return null;
  }

  Future<String?> remove(SoundboardSound sound) async {
    final library = _library;
    if (library == null) return ServerSession.gone;
    final result = await library.deleteSound(
      soundId: sound.id,
      objectPath: sound.objectPath,
    );
    if (!result.success) {
      // Refused, or somebody else removed it first: either way the list is
      // read again rather than left showing a clip that may be gone.
      unawaited(refresh());
      return result.error;
    }
    _reads++;
    if (!isClosed) {
      emit(
        state.copyWith(
          sounds: [
            for (final s in state.sounds)
              if (s.id != sound.id) s,
          ],
        ),
      );
    }
    return null;
  }
}
