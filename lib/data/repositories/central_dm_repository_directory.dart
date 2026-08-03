part of 'central_dm_repository.dart';

/// The `dm_profiles` directory — how a user is found before any contact
/// exists. Rows are public by design (a handle, a display name, and the chat
/// public key needed to seal a first message), which is the whole point of
/// the discovery tier.
mixin _CentralDmDirectoryMixin {
  SupabaseClient get _client;

  // ──────────────────────────────────────────────────────────
  // Directory (dm_profiles)
  // ──────────────────────────────────────────────────────────

  /// The caller's own directory row, or success(null) when not created yet.
  Future<APIResponse> getMyProfile() async {
    try {
      final row = await _client
          .from('dm_profiles')
          .select()
          .eq('user_id', _client.auth.currentUser!.id)
          .maybeSingle();
      return APIResponse.success(row);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Create or refresh the caller's directory row. Fails with a unique
  /// violation when the handle is taken by someone else.
  Future<APIResponse> upsertProfile({
    required String handle,
    required String chatPublicKey,
    required String signingPublicKey,
  }) async {
    try {
      await _client.from('dm_profiles').upsert({
        'user_id': _client.auth.currentUser!.id,
        'handle': handle,
        'chat_public_key': chatPublicKey,
        'signing_public_key': signingPublicKey,
      }, onConflict: 'user_id');
      return APIResponse.success(null);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        return APIResponse(
          success: false,
          error: 'That handle is already taken',
          errorCode: 'handle_taken',
        );
      }
      return APIResponse.error(e.message);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Prefix-search the directory (excluding the caller).
  Future<APIResponse> searchHandles(String prefix) async {
    try {
      final rows = await _client
          .from('dm_profiles')
          .select()
          .ilike('handle', '$prefix%')
          .neq('user_id', _client.auth.currentUser!.id)
          .order('handle', ascending: true)
          .limit(10);
      return APIResponse.success(rows);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Fetch directory rows for a set of user ids.
  Future<APIResponse> getProfiles(List<String> userIds) async {
    try {
      final rows = await _client
          .from('dm_profiles')
          .select()
          .inFilter('user_id', userIds);
      return APIResponse.success(rows);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
