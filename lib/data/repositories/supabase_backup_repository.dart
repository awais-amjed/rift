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
/// Table schema expected on the central server:
/// ```sql
/// create table backups (
///   id          uuid primary key default gen_random_uuid(),
///   user_id     uuid references auth.users not null unique,
///   backup_json text not null,
///   updated_at  timestamptz default now()
/// );
/// alter table backups enable row level security;
/// create policy "own backup" on backups
///   using (auth.uid() = user_id)
///   with check (auth.uid() = user_id);
/// ```
class SupabaseBackupRepository {
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

  /// Uploads (upserts) the encrypted backup JSON for the current user.
  Future<APIResponse> uploadBackup(String backupJson) async {
    try {
      final uid = _requireUid();
      if (uid == null) return APIResponse.error('Not signed in.');
      await _client.from('backups').upsert({
        'user_id': uid,
        'backup_json': backupJson,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
      return APIResponse.success(null);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Downloads the encrypted backup JSON for the current user.
  ///
  /// On success [APIResponse.data] is the backup JSON string, or `null`
  /// if no backup has been uploaded yet.
  Future<APIResponse> downloadBackup() async {
    try {
      final uid = _requireUid();
      if (uid == null) return APIResponse.error('Not signed in.');
      final data = await _client
          .from('backups')
          .select('backup_json')
          .eq('user_id', uid)
          .maybeSingle();
      return APIResponse.success(data?['backup_json'] as String?);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  String? _requireUid() => currentUser?.id;
}
