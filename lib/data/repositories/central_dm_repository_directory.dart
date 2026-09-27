part of 'central_dm_repository.dart';

/// The central `users` table — the account row, and the handle and public keys
/// behind it.
///
/// It is no longer a *directory*. Rows used to be readable
/// by every signed-in account, which made the whole membership enumerable by
/// anyone who had signed up; now the policy is relationship-scoped and there is
/// nothing here that searches. Turning a handle into a person is
/// `requestFriendByHandle` in the friends mixin, which resolves and asks in the
/// same statement so that a lookup always costs the caller a visible row in
/// somebody's Pending list.
///
/// It was `dm_profiles` until the schema was written down as migrations: it is
/// the account row, and it will hold more than a directory profile.
mixin _CentralDmDirectoryMixin {
  SupabaseClient get _client;

  // ──────────────────────────────────────────────────────────
  // Directory (users)
  // ──────────────────────────────────────────────────────────

  /// The caller's own directory row, or success(null) when not created yet.
  Future<APIResponse> getMyProfile() async {
    try {
      final row = await _client
          .from('users')
          .select()
          .eq('id', _client.auth.currentUser!.id)
          .maybeSingle();
      return APIResponse.success(row);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Create or refresh the caller's directory row. Fails with a unique
  /// violation when the handle is taken by someone else.
  ///
  /// Through `claim_handle` rather than a table upsert: PostgREST puts every
  /// column of the payload into the `DO UPDATE` clause, `id` among them, and
  /// `id` is not in the table's UPDATE grant — so the upsert was refused with
  /// "permission denied for table users" on the very first claim.
  Future<APIResponse> upsertProfile({
    required String handle,
    required String chatPublicKey,
    required String signingPublicKey,
  }) async {
    try {
      await _client.rpc(
        'claim_handle',
        params: {
          'p_handle': handle,
          'p_chat_public_key': chatPublicKey,
          'p_signing_public_key': signingPublicKey,
        },
      );
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

  /// Fetch directory rows for a set of user ids — the handles and keys behind
  /// an existing conversation list.
  ///
  /// Through `directory_profiles` rather than a table read, because
  /// what a table read answers depends on a policy — and the
  /// question this asks is narrower and more stable than the policy's.
  ///
  /// The RPC answers for people the caller has already exchanged messages
  /// with, which is exactly the conversation list and nothing else. That it
  /// keeps answering after a block or an unfriend is the point: a DM key is
  /// derived from the peer's published X25519 key and re-read on every launch,
  /// so a version of this that stopped answering would quietly make the other
  /// person's copy of the conversation undecryptable. Nothing deleted; it
  /// simply stops opening.
  Future<APIResponse> getProfiles(List<String> userIds) async {
    try {
      final rows = await _client.rpc(
        'directory_profiles',
        params: {'p_ids': userIds},
      );
      return APIResponse.success(rows);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
