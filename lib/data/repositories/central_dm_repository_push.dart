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
}
