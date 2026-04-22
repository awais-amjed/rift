import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../classes/api_response.dart';

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
class SupabaseBackupRepository {
  static const _bucket = 'backups';

  /// The shared Supabase client initialised in main() via Supabase.initialize().
  SupabaseClient get _client => Supabase.instance.client;

  // ── Auth ──────────────────────────────────────────────────

  User? get currentUser => _client.auth.currentUser;

  bool get isSignedIn => currentUser != null;

  /// Signs up a new user on the central server.
  ///
  /// On success [APIResponse.data] is a map:
  ///   `{ 'user': User?, 'needsConfirmation': bool }`
  Future<APIResponse> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
      );

      // Session is null → email confirmation required.
      if (response.session == null) {
        return APIResponse.success({
          'user': null,
          'needsConfirmation': true,
        });
      }

      final user = response.user;
      if (user == null) {
        return APIResponse.error('Sign-up succeeded but no user was returned.');
      }
      return APIResponse.success({
        'user': user,
        'needsConfirmation': false,
      });
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Signs in an existing user.
  ///
  /// On success [APIResponse.data] is the [User].
  Future<APIResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) {
        return APIResponse.error('Sign-in succeeded but no user was returned.');
      }
      return APIResponse.success(user);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Signs out the current user.
  Future<APIResponse> signOut() async {
    try {
      await _client.auth.signOut();
      return APIResponse.success(null);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  // ── Backup ────────────────────────────────────────────────

  /// Uploads (upserts) the encrypted backup for the current user.
  ///
  /// Stored as `{uid}/vault.json` in the `backups` bucket.
  Future<APIResponse> uploadBackup(String backupJson) async {
    try {
      final uid = _requireUid();
      if (uid == null) return APIResponse.error('Not signed in.');

      final bytes = utf8.encode(backupJson);
      await _client.storage.from(_bucket).uploadBinary(
            '$uid/vault.json',
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/json',
              upsert: true,
            ),
          );

      return APIResponse.success(null);
    } catch (e) {
      return APIResponse.error(e);
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
      // Object not found — no backup uploaded yet.
      if (e.statusCode == '404' || (e.message.contains('not found'))) {
        return APIResponse.success(null);
      }
      return APIResponse.error(e);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  String? _requireUid() => currentUser?.id;
}