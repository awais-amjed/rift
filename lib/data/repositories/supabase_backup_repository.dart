import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../supabase_config.dart';
import '../central_failure.dart';
import '../classes/api_response.dart';

part 'supabase_backup_repository_account.dart';

/// Repository that manages all interactions with the central Supabase server
/// used for cloud backup.
///
/// Every public method returns [APIResponse] — errors are logged automatically
/// via [APIResponse.error] and the cubit only needs to check [APIResponse.success].
///
/// Uses [supabase_flutter] so the auth session is automatically persisted
/// across app restarts via platform-native secure storage.
///
/// Backup storage:
///   Bucket : `backups`  (private, RLS-enforced)
///   Object : `{uid}/vault.json`
///
/// Each authenticated user can only read/write their own object via storage
/// policies bound to `auth.uid()`.
///
/// The account itself is signed in and managed in
/// `supabase_backup_repository_account.dart`.
class SupabaseBackupRepository with _CentralAccountMixin {
  static const _bucket = 'backups';

  /// The shared Supabase client initialised in main() via Supabase.initialize().
  @override
  SupabaseClient get _client => Supabase.instance.client;

  // ── Backup ────────────────────────────────────────────────

  /// Uploads (upserts) the encrypted backup for the current user.
  ///
  /// Stored as `{uid}/vault.json` in the `backups` bucket.
  Future<APIResponse> uploadBackup(String backupJson) async {
    try {
      final uid = _requireUid();
      if (uid == null) return APIResponse.error('Not signed in.');

      final bytes = utf8.encode(backupJson);
      // Whatever was read before is not what is there after this.
      _lastRead = null;
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            '$uid/vault.json',
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/json',
              upsert: true,
            ),
          );

      return APIResponse.success(null);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  /// Downloads the encrypted backup for the current user.
  ///
  /// On success [APIResponse.data] is the backup JSON string, or `null`
  /// if no backup has been uploaded yet.
  ///
  /// Asks Storage which version is stored first, and downloads only when it
  /// is not the one last read. The backup is read on sign-in (three times),
  /// before every automatic upload and on every return to the window, and it
  /// may be megabytes; nearly every one of those found what the last had.
  /// Every upload gets a new version, even of the same bytes, so a version
  /// seen twice is the same object (measured on central's Storage, Nov 27).
  Future<APIResponse> downloadBackup() async {
    try {
      final uid = _requireUid();
      if (uid == null) return APIResponse.error('Not signed in.');

      final version = await _storedVersion(uid);
      final kept = _lastRead;
      if (version != null &&
          kept != null &&
          kept.uid == uid &&
          kept.version == version) {
        return APIResponse.success(kept.json);
      }

      final bytes = await _client.storage
          .from(_bucket)
          .download('$uid/vault.json');
      final json = utf8.decode(bytes);
      // Kept under the version asked *before* the download: one uploaded in
      // between is then a version this copy does not claim, and the next
      // read downloads again rather than keeping the older bytes.
      _lastRead = version == null
          ? null
          : (uid: uid, version: version, json: json);
      return APIResponse.success(json);
    } on StorageException catch (e) {
      if (CentralFailure.isUnreachable(e)) return CentralFailure.response(e);
      // Object not found — no backup uploaded yet.
      if (e.statusCode == '404' || (e.message.contains('not found'))) {
        _lastRead = null;
        return APIResponse.success(null);
      }
      return CentralFailure.response(e);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  /// The backup last downloaded, with whose it was and the Storage version
  /// it was read as. One copy for the app: each cubit holds a repository of
  /// its own, and the sign-in reads are spread across two of them.
  static ({String uid, String version, String json})? _lastRead;

  /// The version Storage holds for the backup, or null when it cannot say
  /// (no backup yet, or no answer): the caller then downloads, as before.
  Future<String?> _storedVersion(String uid) async {
    try {
      final info = await _client.storage.from(_bucket).info('$uid/vault.json');
      return '${info.version} ${info.etag ?? ''}';
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  String? _requireUid() => currentUser?.id;
}
