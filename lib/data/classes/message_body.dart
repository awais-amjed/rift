import 'dart:convert';

import 'attachment.dart';
import 'link_preview.dart';

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

  /// What the sender saw at the first link, if they chose to send it. Sealed
  /// with the text, so readers never fetch the page — see [LinkPreview].
  final LinkPreview? preview;

  /// The id of the message this one answers, within the same conversation.
  ///
  /// **An id and nothing else — never a copy of what was said.** A snapshot
  /// would render when the original is gone, which is the whole temptation,
  /// and it would be text the *replier* wrote being drawn under the original
  /// author's name. Readers resolve this against messages they have already
  /// verified, so a reply can quote nothing it could not also point at.
  ///
  /// Sealed rather than a column for the same reason the body is: the id is
  /// the conversation's shape, and the server has no business holding it. A
  /// reply that should ring names its author in `mentions`, which is the
  /// column that exists for waking somebody without reading anything.
  final String? replyToId;

  const MessageBody({
    this.version = currentVersion,
    this.text = '',
    this.attachments = const [],
    this.preview,
    this.replyToId,
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
    if (preview != null) 'prev': preview!.toJson(),
    if (replyToId != null) 're': replyToId,
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
        final prev = decoded['prev'];
        // Anything but a non-empty string is no reference at all. A sender
        // controls this field, and an empty one would resolve to nothing
        // while still drawing the "original unavailable" bar.
        final re = decoded['re'];
        return MessageBody(
          version: decoded['v'] as int? ?? currentVersion,
          text: decoded['text'] as String? ?? '',
          attachments: att,
          preview: prev is Map<String, dynamic>
              ? LinkPreview.fromJson(prev)
              : null,
          replyToId: re is String && re.isNotEmpty ? re : null,
        );
      }
    } catch (_) {
      // Not JSON at all → legacy plain text.
    }
    return MessageBody(text: plaintext);
  }
}
