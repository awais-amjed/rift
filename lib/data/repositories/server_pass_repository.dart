import 'package:supabase_flutter/supabase_flutter.dart';

import '../../logic/helper_methods.dart';
import '../central_failure.dart';

const _passFailedText =
    "Rift couldn't vouch for your account. Try joining again.";

/// The address a pass for this server names: the server's own public one,
/// which `resolve_invite` hands out, or the link's on a server too old to
/// say. Central makes the tag from it and the server accepts no other, so a
/// link reaching the server by another address still joins.
String passAddress({
  required String linkUrl,
  required Map<dynamic, dynamic> data,
}) => switch (data['public_url']) {
  final String url when url.isNotEmpty => url,
  _ => linkUrl,
};

/// A failed invite, in words. A server from before links could need an
/// account has no such column, and says so in PostgREST's terms.
String? inviteErrorText(String? error, {required bool needsAccount}) =>
    needsAccount && error != null && error.contains('needs_account')
    ? 'This server needs a console update before a link can need a Rift '
          'account.'
    : error;

/// Central's answer to `server_pass`, as a pass or a sentence.
({String? pass, String? error}) passFromResponse(Object? data) {
  if (data is Map && data['pass'] is String) {
    return (pass: data['pass'] as String, error: null);
  }
  final code = data is Map ? data['error'] : null;
  return (
    pass: null,
    error: switch (code) {
      'email_unconfirmed' =>
        "Confirm your Rift account's email first, then join again.",
      'not_authenticated' => 'Sign in to Rift again, then join again.',
      _ => _passFailedText,
    },
  );
}

/// Central vouching for the signed-in Rift account to one server
/// (`server_pass` on central), for a link an admin marked as needing an
/// account.
///
/// Asked only for such a link, since central sees the request: which server,
/// for which account. The pass names the identity that will join, so it is
/// worth nothing to anybody who copies it.
class ServerPassRepository {
  SupabaseClient get _client => Supabase.instance.client;

  /// Whether a Rift account is signed in on this device. Privacy mode has
  /// none.
  bool get hasAccount {
    try {
      return _client.auth.currentUser != null;
    } catch (_) {
      // Central's client was never set up (a test, or a start that failed).
      return false;
    }
  }

  Future<({String? pass, String? error})> passFor({
    required String supabaseUrl,
    required String serverId,
    required String publicKey,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'server_pass',
        body: {
          'supabase_url': supabaseUrl,
          'server_id': serverId,
          'public_key': publicKey,
        },
      );
      return passFromResponse(response.data);
    } on FunctionException catch (e) {
      if (CentralFailure.isUnreachable(e)) {
        return (pass: null, error: CentralFailure.response(e).error);
      }
      return passFromResponse(e.details);
    } catch (e) {
      HelperMethods.printDebug('[ServerPass] failed: $e');
      return (pass: null, error: _passFailedText);
    }
  }
}
