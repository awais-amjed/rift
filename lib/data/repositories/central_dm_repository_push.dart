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
  /// FCM rotates the token. The same token for the same account, already
  /// written in the last day, is not written again: every app start wrote it,
  /// for a row that was already there. Once a day still goes through, so
  /// `updated_at` keeps saying when the token was last in use, and a row
  /// central lost is put back by the next day at the latest.
  Future<APIResponse> registerDevice({
    required String token,
    required String platform,
  }) async {
    final mark = await _registrationMark(token);
    if (mark != null && await _registeredRecently(mark)) {
      return APIResponse.success(null);
    }
    try {
      await _client.from('device_tokens').upsert({
        'token': token,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
      if (mark != null) await _rememberRegistered(mark);
      return APIResponse.success(null);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  /// Which account and token a registration was for, hashed: the token is an
  /// address to ring, and the preferences file need not hold one.
  Future<String?> _registrationMark(String token) async {
    final user = _client.auth.currentUser?.id;
    if (user == null) return null;
    final digest = await Sha256().hash(utf8.encode('$user\n$token'));
    return base64Url.encode(digest.bytes);
  }

  static const _registeredKey = 'central_push_registered';
  static const _registerAgainAfter = Duration(days: 1);

  Future<bool> _registeredRecently(String mark) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_registeredKey)?.split(' ');
      if (saved == null || saved.length != 2 || saved[0] != mark) return false;
      final at = DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(saved[1]) ?? 0,
      );
      final age = DateTime.now().difference(at);
      return !age.isNegative && age < _registerAgainAfter;
    } catch (_) {
      return false;
    }
  }

  Future<void> _rememberRegistered(String? mark) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mark == null) {
        await prefs.remove(_registeredKey);
      } else {
        await prefs.setString(
          _registeredKey,
          '$mark ${DateTime.now().millisecondsSinceEpoch}',
        );
      }
    } catch (_) {
      // Only a saving: the next start writes the row again.
    }
  }

  /// Give up this device's registration — on sign-out, so the next person to
  /// use the phone is not told about messages for an account they left.
  Future<APIResponse> unregisterDevice(String token) async {
    try {
      await _client.from('device_tokens').delete().eq('token', token);
      // Signed in again, the account must be written back at once.
      await _rememberRegistered(null);
      return APIResponse.success(null);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  // ── Relaying for a self-hosted server ─────────────────────

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
      if (CentralFailure.isUnreachable(e)) return CentralFailure.response(e);
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
      return CentralFailure.response(e);
    }
  }

  /// Give up this account's other credentials for one server — every one
  /// but [keep], the one the server now holds. A server keeps one credential
  /// at a time, so the rest are slots nothing can use: left by a turn-off
  /// from another admin's account, whose delete cannot reach this one's
  /// rows, or by a server reset that lost its copy. Twenty of them and this
  /// account could turn push on nowhere.
  Future<APIResponse> revokeOtherPushRelays({
    required String supabaseUrl,
    required String serverId,
    required String keep,
  }) async {
    try {
      await _client
          .from('push_relays')
          .delete()
          .eq('supabase_url', supabaseUrl)
          .eq('server_id', serverId)
          .neq('id', keep);
      return APIResponse.success(null);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }

  /// Give up a credential. The server that held it stops being able to ring
  /// anyone through central, and the slot it occupied is free again.
  Future<APIResponse> revokePushRelay(String relayId) async {
    try {
      await _client.from('push_relays').delete().eq('id', relayId);
      return APIResponse.success(null);
    } catch (e) {
      return CentralFailure.response(e);
    }
  }
}
