part of 'central_dm_repository.dart';

/// Where this account's phones are reachable, so central can ring them.
///
/// A row here is a device, not a person: the same account on a phone and a
/// tablet is two rows, and both should ring. The token is the primary key
/// because FCM can hand the same one to a reinstalled app, and a device that
/// changes hands should replace the old owner's row rather than accumulate
/// beside it.
mixin _CentralDmPushMixin {
  SupabaseClient get _client;

  /// Tell central this device can be woken.
  ///
  /// Best-effort and idempotent: it runs on every sign-in and again whenever
  /// FCM rotates the token, so the common case is writing a row that is
  /// already there. `updated_at` is what makes that write worth doing — it is
  /// how a token that has gone quiet for months is eventually recognised as
  /// dead and pruned.
  Future<APIResponse> registerDevice({
    required String token,
    required String platform,
  }) async {
    try {
      await _client.from('device_tokens').upsert({
        'token': token,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
      return APIResponse.success(null);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Give up this device's registration — on sign-out, so the next person to
  /// use the phone is not told about messages for an account they left.
  Future<APIResponse> unregisterDevice(String token) async {
    try {
      await _client.from('device_tokens').delete().eq('token', token);
      return APIResponse.success(null);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  // ──────────────────────────────────────────────────────────
  // Relaying for a self-hosted server
  // ──────────────────────────────────────────────────────────

  /// Mint a credential a self-hosted server can forward pushes over.
  ///
  /// An FCM token is scoped to the Firebase project the app was built against
  /// — Rift's — so a server run by somebody else cannot wake its own members'
  /// phones and has to ask central to. That has to be credentialled or it
  /// would be an open push proxy, and the credential is minted here, by the
  /// signed-in admin of the server in question.
  ///
  /// The secret comes back exactly once. The caller's next act is to write it
  /// into that server's own config, after which neither end can read it again.
  /// Returns `{relay_id, secret}`.
  Future<APIResponse> enrollPushRelay({
    required String supabaseUrl,
    required String serverId,
    String? label,
  }) async {
    try {
      final result = await _client.rpc(
        'enroll_push_relay',
        params: {
          'p_supabase_url': supabaseUrl,
          'p_server_id': serverId,
          'p_label': label,
        },
      );
      return APIResponse.success(result);
    } on PostgrestException catch (e) {
      final known = [
        'too_many_relays',
        'not_authenticated',
      ].firstWhere((code) => e.message.contains(code), orElse: () => '');
      return APIResponse(
        success: false,
        error: known.isNotEmpty ? known : e.message,
        errorCode: known.isNotEmpty ? known : null,
      );
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Give up a credential. The server that held it stops being able to ring
  /// anyone through central, and the slot it occupied is free again.
  Future<APIResponse> revokePushRelay(String relayId) async {
    try {
      await _client.from('push_relays').delete().eq('id', relayId);
      return APIResponse.success(null);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
