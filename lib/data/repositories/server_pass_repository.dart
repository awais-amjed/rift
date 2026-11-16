import 'package:supabase_flutter/supabase_flutter.dart';

import '../../logic/helper_methods.dart';
import '../central_failure.dart';
import '../classes/resolved_invite.dart';

const _passFailedText =
    "Rift couldn't vouch for your account. Try joining again.";

/// Where a join through a link goes, given the server's `resolve_invite`
/// answer [data].
///
/// A link that needs a Rift account carries central's pass, which names one
/// address, and the server accepts only its own. Whoever is handed a pass can
/// read the tag in it, the one the server it names keeps for this account. So
/// such a join goes whole to the address the server gives as its own, and the
/// pass is handed to nobody else: a server naming another's address only sends
/// the join there, where its invite has to work. Any other link, or a server
/// too old to give an address, is joined where the link points.
String joinAddress({
  required String linkUrl,
  required Map<dynamic, dynamic> data,
}) {
  final given = data['public_url'];
  if (!needsAccountIn(data) || given is! String) return linkUrl;
  final own = Uri.tryParse(given.trim());
  final link = Uri.tryParse(linkUrl);
  if (own == null ||
      link == null ||
      !const {'http', 'https'}.contains(own.scheme) ||
      own.host.isEmpty) {
    return linkUrl;
  }
  if (own.scheme == link.scheme &&
      own.host == link.host &&
      own.port == link.port) {
    return linkUrl;
  }
  // The address is put in front of /functions/v1/..., so no slash at the end.
  return given.trim().replaceFirst(RegExp(r'/+$'), '');
}

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
