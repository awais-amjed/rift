import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// What opening one sealed row came to — see ARCHITECTURE.md §4, *Three
/// things a client can do with a row*.
enum SealedOutcome { opened, locked, dropped }

/// Open [envelope], telling a forgery apart from a key this device has wrong.
///
/// The signature is checked first and covers the ciphertext, so once it holds
/// the body is exactly what its author sealed. If it then does not open, the
/// fault is the key this device used — a DM key derived from a peer key that
/// has since changed, a channel key that was wrapped wrong — and the message
/// is **locked**, not dropped: real, from who it says, and unreadable here.
/// Dropping those is what emptied a DM the moment the other person's key
/// changed. A bad signature is still dropped, silently, as before.
///
/// Anything else thrown is left to the caller, which drops the row.
Future<({SealedOutcome outcome, String? plaintext})> openSealed(
  CryptoRepository crypto, {
  required MessageEnvelope envelope,
  required Uint8List messageKey,
  required Uint8List senderPublicKey,
  required String contextId,
}) async {
  try {
    final plaintext = await crypto.openMessage(
      envelope: envelope,
      messageKey: messageKey,
      senderPublicKey: senderPublicKey,
      contextId: contextId,
    );
    return plaintext == null
        ? (outcome: SealedOutcome.dropped, plaintext: null)
        : (outcome: SealedOutcome.opened, plaintext: plaintext);
  } on SecretBoxAuthenticationError {
    return (outcome: SealedOutcome.locked, plaintext: null);
  }
}
