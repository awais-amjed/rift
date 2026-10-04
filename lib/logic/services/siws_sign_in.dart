import 'package:rift_crypto/rift_crypto.dart';

import '../../data/classes/api_response.dart';
import '../../data/repositories/server_repository.dart';

/// Signs in to a server with [identity]'s SIWS key, and gets in even when this
/// device's clock is wrong.
///
/// GoTrue refuses a message dated more than ten minutes from its own clock
/// (`MaximumValidityDuration`). A device whose clock or time zone is off — a PC
/// that also boots Linux and keeps local time in its hardware clock is the
/// usual one — could therefore sign in to no server at all, and every call
/// after the first hour failed with "Invalid or expired token" (a Windows VM
/// twelve hours fast, Oct 4 2026). The refusal carries the server's own time,
/// so the message is signed again at that time and sent once more.
///
/// Shared by the app and the push isolate, which sign in the same way.
Future<APIResponse> siwsSignIn({
  required ServerRepository repository,
  required CryptoRepository crypto,
  required String supabaseUrl,
  required ServerIdentity identity,
}) async {
  Future<APIResponse> signedAt(DateTime? issuedAt) async {
    final signed = await crypto.signSiws(
      keyPair: identity.keyPair,
      publicKeyBytes: identity.publicKeyBytes,
      issuedAt: issuedAt,
    );
    return repository.login(
      supabaseUrl,
      message: signed.message,
      signature: signed.signatureBase64,
    );
  }

  final response = await signedAt(null);
  if (response.success || !isClockRefusal(response.error)) return response;

  final serverTime = response.serverTime;
  final retried = serverTime == null ? response : await signedAt(serverTime);
  if (retried.success || !isClockRefusal(retried.error)) return retried;
  return APIResponse(
    success: false,
    error: clockRefusalMessage(serverTime?.difference(DateTime.now())),
    errorCode: retried.errorCode,
  );
}

/// Whether GoTrue refused a sign-in because of when the message says it was
/// signed. Its own words, passed through by the `login` function: they are
/// the only sign of it.
bool isClockRefusal(String? error) =>
    error != null &&
    (error.contains('issued too far in the future') ||
        error.contains('issued too long ago'));

/// What to tell someone whose sign-in was refused for their clock. [offset] is
/// the server's time less this device's, when the server said what it was.
String clockRefusalMessage(Duration? offset) {
  const fix = 'Set its date, time and time zone correctly, then try again.';
  if (offset == null) {
    return "The server refused the sign-in because this device's clock "
        'looks wrong. $fix';
  }
  final ahead = offset.isNegative;
  final minutes = offset.inMinutes.abs();
  final hours = (minutes / 60).round();
  final amount = minutes < 90
      ? '$minutes minutes'
      : '$hours hour${hours == 1 ? '' : 's'}';
  return "This device's clock is $amount ${ahead ? 'fast' : 'slow'}, so the "
      'server refused the sign-in. $fix';
}
