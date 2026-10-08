part of 'soundboard_cubit.dart';

/// The server's clips: reading them, adding, renaming and removing one, and
/// deleting the local copy of any that vanished.
///
/// Nothing here plays a sound or knows a call exists — the other half of the
/// cubit is the one listening on the data channel.
mixin _SoundboardLibraryMixin on Cubit<SoundboardState> {
  SoundboardApi get _api;

  /// Whose library this is: the watched server.
  String? get _libraryServerId;

  Future<void> refresh() async {
    final serverId = _libraryServerId;
    if (serverId == null) return;

    final result = await _api.listSounds(serverId: serverId);
    // The rail moved while this was in flight; the answer is another
    // server's and drawing it under this one's name would be a lie.
    if (isClosed || _libraryServerId != serverId) return;

    _forgetVanished(serverId: serverId, result: result);

    emit(
      state.copyWith(
        status: result.error == null
            ? SoundboardStatus.ready
            : SoundboardStatus.error,
        serverId: serverId,
        sounds: result.sounds,
        error: result.error,
        clearError: result.error == null,
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
  ///   from a library somebody emptied unless the error is checked.
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
    required ({List<SoundboardSound> sounds, String? error}) result,
  }) {
    if (result.error != null || state.serverId != serverId) return;
    if (state.sounds.isEmpty) return;

    final kept = {for (final sound in result.sounds) sound.objectPath};
    for (final sound in state.sounds) {
      if (kept.contains(sound.objectPath)) continue;
      unawaited(SoundboardCache.instance.forget(sound.objectPath));
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
    final result = await _api.addSound(
      name: name,
      emoji: emoji,
      bytes: bytes,
      contentType: contentType,
      duration: duration,
      serverId: _libraryServerId,
    );
    if (result.error != null) return result.error;
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
    final result = await _api.renameSound(
      soundId: sound.id,
      name: name,
      emoji: emoji,
      serverId: _libraryServerId,
    );
    if (!result.success) return result.error;
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
    final result = await _api.deleteSound(
      soundId: sound.id,
      objectPath: sound.objectPath,
      serverId: _libraryServerId,
    );
    if (!result.success) return result.error;
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
