import 'package:supabase_flutter/supabase_flutter.dart';

import '../../supabase_config.dart' show SupabaseConfig; // kept for doc reference

/// Repository that manages all interactions with the central Supabase server
/// used for cloud backup.
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
///
/// -- Row-level security: users can only access their own row.
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
  /// Returns `null` when the server requires email confirmation
  /// (session is not yet active). Returns the [User] when sign-up
  /// immediately creates a session (e.g. email confirmation is disabled).
  /// Throws [AuthException] on failure.
  Future<({User? user, bool needsConfirmation})> signUp({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );

    // Session is null → email confirmation required.
    if (response.session == null) {
      return (user: null, needsConfirmation: true);
    }

    final user = response.user;
    if (user == null) {
      throw const AuthException('Sign-up succeeded but no user was returned.');
    }
    return (user: user, needsConfirmation: false);
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
