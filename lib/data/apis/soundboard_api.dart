import 'dart:async';
import 'dart:typed_data';

import '../../logic/services/soundboard_cache.dart';
import '../classes/soundboard_sound.dart';
import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';
import '../repositories/soundboard_repository.dart';

/// One server's soundboard library.
///
/// Nothing here holds state — `SoundboardCubit` does, because a picker that
/// opens mid-call cannot wait for a round trip and a new clip has to appear
/// for everyone without one. This is only the four calls and the bytes that
/// go with them, each through [SessionRepository] so an expired token signs
/// in again rather than failing.
class SoundboardApi {
  final ServerSession _target;
  final SoundboardRepository _sounds;

  SoundboardApi(this._target, {SoundboardRepository? sounds})
    : _sounds = sounds ?? SoundboardRepository();

  SessionRepository get _session => _target.session;

  ServerRepository get _repository => _session.repository;

  /// Where this server's clips come from, which the clip cache keys them
  /// under beside their path ([SoundboardCache]). Null with the server gone.
  String? get origin => _target.server?.supabaseUrl;

  /// Whether [objectPath] is one of [serverId]'s own objects, one name deep:
  /// `<serverId>/<name>`, as `SoundboardRepository.buildPath` mints them.
  /// The insert policy checks the first part only, so a row could carry a
  /// path that climbs (`..`, or a backslash on Windows) — dropped here rather
  /// than offered for a press.
  static bool ownsPath(String serverId, String objectPath) {
    final prefix = '$serverId/';
    if (!objectPath.startsWith(prefix)) return false;
    final name = objectPath.substring(prefix.length);
    return RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]*$').hasMatch(name) &&
        !name.contains('..');
  }

  /// Every clip on the server.
  Future<({List<SoundboardSound> sounds, String? error})> listSounds() async {
    final server = _target.server;
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
          if (SoundboardSound.fromJson(r) case final sound
              when ownsPath(server.id, sound.objectPath))
            sound,
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
  }) async {
    final server = _target.server;
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
    unawaited(
      SoundboardCache.instance.warm(
        server.supabaseUrl,
        sound.objectPath,
        bytes,
      ),
    );
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
  }) async {
    final server = _target.server;
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

  /// Remove one: the row, then the object it names. Nothing in the database
  /// can delete the object (see below), so a client that dies between the two
  /// leaves an object nobody points at, which the server's sweep of
  /// unreferenced objects takes later.
  Future<({bool success, String? error})> deleteSound({
    required String soundId,
    required String objectPath,
  }) async {
    final server = _target.server;
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
      unawaited(
        SoundboardCache.instance.forget(server.supabaseUrl, objectPath),
      );
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
      error: response.success ? null : _addFailure(response.error),
    );
  }

  /// One clip's bytes, for a listener that has not heard it before.
  Future<Uint8List?> loadSound(String objectPath) async {
    final server = _target.server;
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
