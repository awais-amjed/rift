import 'package:supabase/supabase.dart';

import '../../supabase_config.dart';

/// Repository that manages all interactions with the central Supabase server
/// used for cloud backup.
///
/// Handles authentication (sign up / sign in / sign out) and CRUD operations
/// on the `backups` table.
///
/// Table schema expected on the central server:
/// ```sql
/// create table backups (
///   id          uuid primary key default gen_random_uuid(),
///   user_id     uuid references auth.users not null unique,
///   backup_json text not null,
///   updated_at  timestamptz default now()
/// );
///
/// -- Row-level security: users can only access their own row.
/// alter table backups enable row level security;
/// create policy "own backup" on backups
///   using (auth.uid() = user_id)
///   with check (auth.uid() = user_id);
/// ```
class SupabaseBackupRepository {
  late final SupabaseClient _client;

  SupabaseBackupRepository() {
    _client = SupabaseClient(
      SupabaseConfig.supabaseUrl,
      SupabaseConfig.supabaseKey,
      authOptions: const AuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );
  }

  // ── Auth ──────────────────────────────────────────────────

  User? get currentUser => _client.auth.currentUser;

  bool get isSignedIn => currentUser != null;

  /// Signs up a new user on the central server.
  /// Returns the [User] on success, throws [AuthException] on failure.
  Future<User> signUp({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw const AuthException('Sign-up succeeded but no user was returned.');
    }
    return user;
  }

  /// Signs in an existing user.
  /// Returns the [User] on success, throws [AuthException] on failure.
  Future<User> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw const AuthException('Sign-in succeeded but no user was returned.');
    }
    return user;
  }

  /// Signs out the current user.
  Future<void> signOut() => _client.auth.signOut();

  // ── Backup ────────────────────────────────────────────────

  /// Uploads (upserts) the encrypted backup JSON for the current user.
  Future<void> uploadBackup(String backupJson) async {
    final uid = _requireUid();
    await _client.from('backups').upsert({
      'user_id': uid,
      'backup_json': backupJson,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  /// Downloads the encrypted backup JSON for the current user.
  /// Returns `null` if no backup has been uploaded yet.
  Future<String?> downloadBackup() async {
    final uid = _requireUid();
    final data = await _client
        .from('backups')
        .select('backup_json')
        .eq('user_id', uid)
        .maybeSingle();
    return data?['backup_json'] as String?;
  }

  // ── Helpers ───────────────────────────────────────────────

  String _requireUid() {
    final uid = currentUser?.id;
    if (uid == null) throw const AuthException('Not signed in.');
    return uid;
  }
}

