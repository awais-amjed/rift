import 'attachment.dart';

/// A message carried into another conversation, as the forwarder describes it.
///
/// **Everything here is a claim, and the UI has to say so.** A forward is
/// re-sealed under the destination's key and signed by the person forwarding
/// it, because the people reading it hold no key to the room it came from —
/// so the original author's signature cannot travel with it and there is
/// nothing for a reader to check. The name, the time and the words below are
/// the forwarder's account of a message, exactly as a screenshot is.
///
/// That is why a forward is drawn as *the forwarder's* message with a quoted
/// block inside it, never as the original author posting somewhere they never
/// were. Same rule as the reply's id-only reference (ARCHITECTURE.md §4,
/// *Three things a client can do with a row*), reached from the other end: a
/// reply can point because the reader shares the room, and a forward cannot.
class ForwardedMessage {
  /// What the original text may run to before it is cut.
  ///
  /// The column caps the whole sealed body at 16 KB and the attachments'
  /// keys go in the same envelope, so a forward of a forward of a wall of
  /// text has to stop somewhere. Cut with an ellipsis rather than refused:
  /// losing the tail of a long message is a smaller surprise than a forward
  /// that will not send.
  static const int maxText = 4000;

  /// The name the forwarder says wrote it.
  final String authorName;

  /// When the forwarder says it was written.
  final DateTime sentAt;

  final String text;

  /// Re-uploaded into the destination's own scope, under a new key — never
  /// the original blob's path. Each server has its own bucket, so pointing
  /// at the source would be a link into a bucket the readers cannot open;
  /// and the sweep that clears orphaned blobs works off the oldest surviving
  /// message *per scope*, so a shared object would be deleted out from under
  /// the copy the moment the original's room trimmed it.
  final List<Attachment> attachments;

  /// Where the forwarder says it came from — "#general in Proxy Test", or a
  /// person's name for a DM. Null when they chose not to say, or when there
  /// was nothing sensible to name.
  final String? source;

  const ForwardedMessage({
    required this.authorName,
    required this.sentAt,
    this.text = '',
    this.attachments = const [],
    this.source,
  });

  ForwardedMessage withAttachments(List<Attachment> attachments) =>
      ForwardedMessage(
        authorName: authorName,
        sentAt: sentAt,
        text: text,
        attachments: attachments,
        source: source,
      );

  Map<String, dynamic> toJson() => {
    'by': authorName,
    'at': sentAt.toUtc().toIso8601String(),
    if (text.isNotEmpty) 'text': text,
    if (attachments.isNotEmpty)
      'att': attachments.map((a) => a.toJson()).toList(),
    if (source != null) 'src': source,
  };

  /// Read a forward out of a decoded body, or null if there is not one.
  ///
  /// Hostile by assumption: this arrived inside somebody else's message and
  /// the fields are theirs to fill. A malformed one is dropped whole rather
  /// than half-rendered, because half a forward is a quote with no
  /// attribution — which is the one thing this must never draw.
  static ForwardedMessage? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final name = raw['by'];
    final at = DateTime.tryParse('${raw['at']}');
    if (name is! String || name.isEmpty || at == null) return null;

    final text = raw['text'] is String ? raw['text'] as String : '';
    final source = raw['src'];
    return ForwardedMessage(
      authorName: name,
      sentAt: at,
      // Clipped on the way in as well as on the way out. The cap is this
      // client's rule about what it will draw, and the sender is not the one
      // enforcing it.
      text: text.length <= maxText ? text : text.substring(0, maxText),
      attachments: _attachmentsIn(raw['att']),
      source: source is String && source.isNotEmpty ? source : null,
    );
  }

  static List<Attachment> _attachmentsIn(Object? raw) {
    if (raw is! List) return const [];
    final out = <Attachment>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      // One unreadable attachment costs its own thumbnail, not the whole
      // forward — the text beside it is still worth showing.
      try {
        out.add(Attachment.fromJson(entry));
      } catch (_) {
        continue;
      }
    }
    return out;
  }
}
