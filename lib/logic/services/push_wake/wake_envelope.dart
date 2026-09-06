import 'dart:typed_data';

import 'package:rift_crypto/rift_crypto.dart';

import '../../../data/classes/message_body.dart';

/// Open and verify one envelope from the push background isolate, returning
/// its text.
///
/// Null for anything that fails, by the same rule the app renders by: a
/// message that does not verify is never shown — and a notification is showing
/// it. The isolate is the one place where being lax would be invisible, since
/// nobody is looking at a list to notice the row is missing.
///
/// [senderKeyB64] overrides the row's own attested sender key, for the reads
/// that don't carry one (a DM conversation summary names the peer's key
/// beside the envelope rather than inside it).
Future<String?> openWakeEnvelope(
  CryptoRepository crypto,
  Map<String, dynamic> row, {
  required Uint8List key,
  required String contextId,
  String? senderKeyB64,
}) async {
  final sender = senderKeyB64 ?? row['sender_public_key'] as String?;
  if (sender == null) return null;
  try {
    final plaintext = await crypto.openMessage(
      envelope: MessageEnvelope.fromJson(row),
      messageKey: key,
      senderPublicKey: CryptoRepository.fromBase64(sender),
      contextId: contextId,
    );
    if (plaintext == null) return null;
    return MessageBody.decode(plaintext).text;
  } catch (_) {
    return null;
  }
}
