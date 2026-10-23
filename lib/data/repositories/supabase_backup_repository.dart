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
  Future<APIResponse> downloadBackup() async {
    try {
      final uid = _requireUid();
      if (uid == null) return APIResponse.error('Not signed in.');

      final bytes = await _client.storage
          .from(_bucket)
          .download('$uid/vault.json');

      return APIResponse.success(utf8.decode(bytes));
    } on StorageException catch (e) {
      if (CentralFailure.isUnreachable(e)) return CentralFailure.response(e);
      // Object not found — no backup uploaded yet.
      if (e.statusCode == '404' || (e.message.contains('not found'))) {
        return APIResponse.success(null);
      }
      return CentralFailure.response(e);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  String? _requireUid() => currentUser?.id;
}
