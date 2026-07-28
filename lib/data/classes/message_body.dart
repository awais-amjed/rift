import 'dart:convert';

import 'attachment.dart';

/// The structured content of a chat message — what actually gets sealed into a
/// [MessageEnvelope] as the encrypted plaintext (ARCHITECTURE.md §4).
///
/// Historically a message's plaintext was a bare text string. To carry
/// attachments (and future rich content) without touching the envelope wire
/// format, tables, or signatures, the sealed plaintext is now a small tagged
/// JSON object. Decoding is **backward compatible**: any plaintext that isn't
/// our tagged JSON — every pre-existing message — is treated as plain text.
class MessageBody {
  /// Body schema version. Bumped only on an incompatible shape change.
  static const int currentVersion = 1;

  /// Marker distinguishing our JSON body from an arbitrary text message that
  /// merely happens to be valid JSON.
  static const String _tag = 'rift.msg';

  final int version;
  final String text;
  final List<Attachment> attachments;

  const MessageBody({
    this.version = currentVersion,
    this.text = '',
    this.attachments = const [],
  });

  bool get isEmpty => text.trim().isEmpty && attachments.isEmpty;

  /// Serialize to the string that gets encrypted + signed. A pure text message
  /// with no attachments still encodes as the tagged object (senders are always
  /// current-version); readers accept both shapes.
  String encode() => jsonEncode({
    't': _tag,
    'v': version,
    'text': text,
    if (attachments.isNotEmpty)
      'att': attachments.map((a) => a.toJson()).toList(),
  });

  /// Parse a decrypted plaintext into a body. Anything that isn't our tagged
  /// JSON object is wrapped verbatim as a text-only body, so legacy messages
  /// (and any plain string) always render.
  factory MessageBody.decode(String plaintext) {
    try {
      final decoded = jsonDecode(plaintext);
      if (decoded is Map<String, dynamic> && decoded['t'] == _tag) {
        final att =
            (decoded['att'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(Attachment.fromJson)
                .toList() ??
            const <Attachment>[];
        return MessageBody(
          version: decoded['v'] as int? ?? currentVersion,
          text: decoded['text'] as String? ?? '',
          attachments: att,
        );
      }
    } catch (_) {
      // Not JSON at all → legacy plain text.
    }
    return MessageBody(text: plaintext);
  }
}
