part of 'server_repository.dart';

/// The soundboard library on a self-hosted server (`soundboard_sounds`).
///
/// Ordinary table calls, all four of them: an INSERT here carries no secret
/// and grants nothing, so a policy says all of it rather than an RPC. What a
/// client may write is the column grant — `server_id` and `created_by` are not
/// in it and are stamped, and `object_path` is insert-only so a clip cannot be
/// repointed at other bytes behind the caches already holding the old ones.
///
/// Playing a clip is not here, and not anywhere else in this repository: a
/// press is a packet on the call's data channel. This is only the library.
mixin _SoundboardApiMixin {
  ServerDb get _db;

  /// Every clip on the caller's server, newest last — the order they were
  /// added in, which is the order a picker reads best in.
  Future<APIResponse> listSounds(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('soundboard_sounds')
          .select(
            'id, name, emoji, object_path, duration_ms, bytes, '
            'created_by, created_at',
          )
          .order('created_at');
      return {'sounds': (rows as List).cast<Map<String, dynamic>>()};
    });
  }

  /// Add one, after its bytes have already landed at [objectPath].
  ///
  /// That order matters: the upload is what the size limit is enforced on, so
  /// a row written first would be a clip in the picker with nothing behind it
  /// for as long as the upload takes to fail.
  Future<APIResponse> createSound(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String name,
    String? emoji,
    required String objectPath,
    required int durationMs,
    required int bytes,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('soundboard_sounds')
          .insert({
            'name': name,
            'emoji': emoji,
            'object_path': objectPath,
            'duration_ms': durationMs,
            'bytes': bytes,
          })
          .select(
            'id, name, emoji, object_path, duration_ms, bytes, '
            'created_by, created_at',
          );
      return (rows as List).first as Map<String, dynamic>;
    });
  }

  /// Rename or re-label one. The bytes stay where they are.
  Future<APIResponse> renameSound(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String soundId,
    required String name,
    String? emoji,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      await db
          .from('soundboard_sounds')
          .update({'name': name, 'emoji': emoji})
          .eq('id', soundId);
      return {'renamed': true};
    });
  }

  /// Remove one. The object in the bucket goes with the row — a trigger does
  /// it, so there is nothing to delete here and nothing left behind if this
  /// client dies between the two calls it would otherwise have made.
  Future<APIResponse> deleteSound(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String soundId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      await db.from('soundboard_sounds').delete().eq('id', soundId);
      return {'deleted': true};
    });
  }
}
