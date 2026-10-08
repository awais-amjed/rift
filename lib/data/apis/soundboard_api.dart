import 'dart:async';
import 'dart:typed_data';

import '../../logic/services/soundboard_cache.dart';
import '../classes/soundboard_sound.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/soundboard_repository.dart';

/// The soundboard library for [serverId], or for the selected server.
///
/// Nothing here holds state — `SoundboardCubit` does, because a picker that
/// opens mid-call cannot wait for a round trip and a new clip has to appear
/// for everyone without one. This is only the four calls and the bytes that
/// go with them, each through [SessionRepository] so an expired token signs
/// in again rather than failing.
class SoundboardApi {
  final SessionRepository _session;
  final SoundboardRepository _sounds;

  SoundboardApi({
    required SessionRepository session,
    SoundboardRepository? sounds,
  }) : _session = session,
       _sounds = sounds ?? SoundboardRepository();

  ServerRepository get _repository => _session.repository;

  /// Every clip on the server.
  Future<({List<SoundboardSound> sounds, String? error})> listSounds({
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) {
      return (sounds: const <SoundboardSound>[], error: 'No server');
    }

    final response = await _session.callFor(
      server,
      (token) => _repository.listSounds(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      ),
    );
    if (!response.success) {
      return (
        sounds: <SoundboardSound>[],
        error: response.error ?? 'Could not load the soundboard',
      );
    }

    final rows =
        (response.data as Map<String, dynamic>)['sounds'] as List? ?? const [];
    return (
      sounds: [
        for (final r in rows.cast<Map<String, dynamic>>())
          SoundboardSound.fromJson(r),
      ],
      error: null,
    );
  }

  /// Upload [bytes] and add the clip that names them.
  ///
  /// The bytes go first on purpose. The size limit is enforced on the upload,
  /// so a row written first would leave a clip in everybody's picker with
  /// nothing behind it for as long as the upload took to be refused. The other
  /// way round, a failed insert leaves an unreferenced object — which the
  /// uploader can simply try again over, because the path was never published.
  Future<({SoundboardSound? sound, String? error})> addSound({
    required String name,
    String? emoji,
    required Uint8List bytes,
    required String contentType,
    required Duration duration,
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) return (sound: null, error: 'No server');

    final uploaded = await _session.callFor(
      server,
      (token) => _sounds.upload(
        baseUrl: server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        serverId: server.id,
        data: bytes,
        contentType: contentType,
      ),
    );
    if (!uploaded.success) {
      return (sound: null, error: uploaded.error ?? 'Could not upload that');
    }

    final path = uploaded.data as String;
    final created = await _session.callFor(
      server,
      (token) => _repository.createSound(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        name: name,
        emoji: emoji,
        objectPath: path,
        durationMs: duration.inMilliseconds,
        bytes: bytes.length,
      ),
    );
    if (!created.success) {
      return (sound: null, error: _addFailure(created.error));
    }

    final sound = SoundboardSound.fromJson(
      (created.data as Map).cast<String, dynamic>(),
    );
    // The uploader's own copy, so their first press does not fetch back what
    // they just sent.
    unawaited(SoundboardCache.instance.warm(sound.objectPath, bytes));
    return (sound: sound, error: null);
  }

  /// The database raises a bare token; everything else is Postgres's own
  /// prose, which is not for reading out to somebody adding an airhorn.
  static String _addFailure(String? error) {
    final raw = error ?? '';
    if (raw.contains('soundboard_full')) {
      return 'This server\'s soundboard is full — remove a clip first.';
    }
    if (raw.contains('soundboard_sounds_server_id_name_key') ||
        raw.contains('duplicate key')) {
      return 'There is already a clip called that.';
    }
    if (raw.contains('row-level security') || raw.contains('permission')) {
      return 'You cannot change this server\'s soundboard.';
    }
    if (raw.contains('violates check constraint')) {
      return 'The server would not take that clip — check its name and '
          'length.';
    }
    return raw.isEmpty ? 'Could not add that clip' : raw;
  }

  /// Rename or re-label one.
  Future<({bool success, String? error})> renameSound({
    required String soundId,
    required String name,
    String? emoji,
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) return (success: false, error: 'No server');

    final response = await _session.callFor(
      server,
      (token) => _repository.renameSound(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        soundId: soundId,
        name: name,
        emoji: emoji,
      ),
    );
    return (
      success: response.success,
      error: response.success ? null : _addFailure(response.error),
    );
  }

  /// Remove one. A trigger takes the bytes with the row, so there is one call
  /// here and nothing left over if this client dies halfway.
  Future<({bool success, String? error})> deleteSound({
    required String soundId,
    required String objectPath,
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) return (success: false, error: 'No server');

    final response = await _session.callFor(
      server,
      (token) => _repository.deleteSound(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        soundId: soundId,
      ),
    );
    if (response.success) {
      unawaited(SoundboardCache.instance.forget(objectPath));
      // The row is gone, so the picker is already right. The file is a
      // second call because nothing in the database can make it: Storage
      // refuses a direct DELETE on its own table, and doing it there would
      // only drop the row and leave the bytes on disk anyway. Unawaited and
      // unreported for the same reason it runs second — an object nobody
      // points at costs space, and there is nothing useful to tell somebody
      // who has already watched the clip disappear.
      unawaited(
        _session.callFor(
          server,
          (token) => _sounds.deleteObject(
            baseUrl: server.supabaseUrl,
            anonKey: server.supabaseKey ?? '',
            bearerToken: token,
            path: objectPath,
          ),
        ),
      );
    }
    return (
      success: response.success,
      error: response.success
          ? null
          : response.error ?? 'Could not remove that clip',
    );
  }

  /// One clip's bytes, for a listener that has not heard it before.
  Future<Uint8List?> loadSound(String objectPath, {String? serverId}) async {
    final server = _session.target(serverId);
    if (server == null) return null;

    final response = await _session.callFor(
      server,
      (token) => _sounds.download(
        baseUrl: server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        path: objectPath,
      ),
    );
    if (!response.success) return null;
    return response.data as Uint8List;
  }
}
