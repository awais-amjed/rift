part of 'server_repository.dart';

/// Waking a member's phone for a message on this server.
///
/// The two halves of it sit on opposite sides of a trust line, which is why
/// they are two different transports. A **device registration** is the
/// member's own row and goes straight to the table under RLS. The **relay
/// credential** is the server's, has no policy and no grant at all, and can
/// only be written by an admin through an edge function — because the secret
/// in it is what proves a forward request came from this server, and nothing
/// that can be read back by a client may hold it.
mixin _PushApiMixin {
  ServerDb get _db;
  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  });

  /// Tell this server the calling device can be woken.
  ///
  /// Best-effort and idempotent: it runs on every session and again whenever
  /// FCM rotates the token, so the common case is rewriting a row that is
  /// already there. `updated_at` is what makes that worth doing — a row nobody
  /// has refreshed in two months belongs to a device that has not opened Rift
  /// in two months, and the nightly sweep in `003_push.sql` takes it away.
  ///
  /// Registered whether or not the server has push turned on. A token costs a
  /// row, and pre-registering is what lets an admin enable push and have it
  /// work for everyone already there instead of only for whoever signs in next.
  Future<APIResponse> registerDevice(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String token,
    required String platform,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      // `user_id` is deliberately not sent: a BEFORE trigger stamps it from
      // auth.uid(), so a client cannot register a token against someone else's
      // account and be woken for their messages.
      return db.from('device_tokens').upsert({
        'token': token,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    });
  }

  /// Give up a device's registration — on leaving the server, so the phone
  /// stops being woken for a place it is no longer in.
  Future<APIResponse> unregisterDevice(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String token,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.from('device_tokens').delete().eq('token', token);
    });
  }

  /// Whether this server can currently ring its members' phones. Admin only —
  /// the answer is the existence of the config row, never its contents.
  Future<APIResponse> pushStatus(String supabaseUrl, {String? bearerToken}) {
    return _post(supabaseUrl, 'configure_push', const {
      'status': true,
    }, bearerToken: bearerToken);
  }

  /// Point this server at a relay credential its admin enrolled on central.
  ///
  /// The secret passes through the admin's client once, on its way from
  /// central's `enroll_push_relay` to here, and is never readable again from
  /// either end. Re-enrolling is how it is replaced.
  Future<APIResponse> configurePush(
    String supabaseUrl, {
    String? bearerToken,
    required String endpoint,
    required String relayId,
    required String secret,
  }) {
    return _post(supabaseUrl, 'configure_push', {
      'endpoint': endpoint,
      'relay_id': relayId,
      'secret': secret,
    }, bearerToken: bearerToken);
  }

  /// Stop ringing. The credential stays enrolled on central until it is
  /// revoked there, but this server no longer holds it.
  Future<APIResponse> disablePush(String supabaseUrl, {String? bearerToken}) {
    return _post(supabaseUrl, 'configure_push', const {
      'disable': true,
    }, bearerToken: bearerToken);
  }
}
