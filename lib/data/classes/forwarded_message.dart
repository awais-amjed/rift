import 'package:equatable/equatable.dart';

import 'attachment.dart';

/// Words and files carried into another conversation, and nothing else.
///
/// **No author and no origin — deliberately, and it is the important part
/// of the design.** A forward crosses into rooms whose readers were never
/// in the one it came from, so naming the channel or the server would tell
/// them a place exists that they cannot see and were not meant to know
/// about. On a private server that is the whole of what there was to keep.
/// The same is true at a smaller scale inside one server, between a private
/// channel and a public one.
///
/// Dropping the author costs nothing and settles a second question. The
/// content is re-sealed under the destination's key and signed by the
/// forwarder, so the original author's signature does not travel and there
/// would be nothing for a reader to check — an attribution here could only
/// ever have been a claim. Rather than draw one and caption it as
/// unverifiable, there is none: a forward says *that* it is a forward, and
/// the words are the forwarder's to stand behind.
class ForwardedMessage extends Equatable {
  /// What the original text may run to before it is cut.
  ///
  /// The column caps the whole sealed body at 16 KB and the attachments'
  /// keys go in the same envelope, so a forward of a forward of a wall of
  /// text has to stop somewhere. Cut with an ellipsis rather than refused:
  /// losing the tail of a long message is a smaller surprise than a forward
  /// that will not send.
  static const int maxText = 4000;

  final String text;

  /// Re-uploaded into the destination's own scope, under a new key — never
  /// the original blob's path. Each server has its own bucket, so pointing
  /// at the source would be a link into a bucket the readers cannot open;
  /// and the sweep that clears orphaned blobs works off the oldest surviving
  /// message *per scope*, so a shared object would be deleted out from under
  /// the copy the moment the original's room trimmed it.
  final List<Attachment> attachments;

  const ForwardedMessage({this.text = '', this.attachments = const []});

  bool get isEmpty => text.trim().isEmpty && attachments.isEmpty;

  ForwardedMessage withAttachments(List<Attachment> attachments) =>
      ForwardedMessage(text: text, attachments: attachments);

  Map<String, dynamic> toJson() => {
    if (text.isNotEmpty) 'text': text,
    if (attachments.isNotEmpty)
      'att': attachments.map((a) => a.toJson()).toList(),
  };

  /// Read a forward out of a decoded body, or null if there is not one.
  ///
  /// Hostile by assumption: this arrived inside somebody else's message and
  /// the fields are theirs to fill. A forward carrying neither words nor
  /// files is dropped — an empty card saying "Forwarded" reads as something
  /// that failed to load rather than as something that was sent.
  static ForwardedMessage? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;

    final text = raw['text'] is String ? raw['text'] as String : '';
    final forwarded = ForwardedMessage(
      // Clipped on the way in as well as on the way out. The cap is this
      // client's rule about what it will draw, and the sender is not the
      // one enforcing it.
      text: text.length <= maxText ? text : text.substring(0, maxText),
      attachments: _attachmentsIn(raw['att']),
    );
    return forwarded.isEmpty ? null : forwarded;
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

  @override
  List<Object?> get props => [text, attachments];
}
