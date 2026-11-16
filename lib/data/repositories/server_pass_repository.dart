import 'package:supabase_flutter/supabase_flutter.dart';

import '../../logic/helper_methods.dart';
import '../central_failure.dart';

/// What a link that needs a Rift account says to somebody without one. The
/// server words its own refusal the same way, for an app too old to ask.
const accountRequiredText =
    'This link needs a Rift account. Sign in to Rift, or ask a member for '
    'another link.';

const _passFailedText =
    "Rift couldn't vouch for your account. Try joining again.";

/// The refusal to show before signing in to a server at all, or null to go on.
String? joinNeedsAccountError({
  required bool needsAccount,
  required bool hasAccount,
}) => needsAccount && !hasAccount ? accountRequiredText : null;

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
