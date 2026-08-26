import '../../data/enums/notification_level.dart';
import 'message_markup.dart';

/// What a notification about a chat message says.
///
/// Pure, and shared by every path that raises one — the open channel, the DM
/// inbox scan, and the push background isolate — because they must agree.
/// Being told "Alice mentioned you in #general" by one of them and "Alice in
/// #general" by another, for the same message, is the kind of difference
/// nobody can explain later.
class ChatNotice {
  final String title;
  final String body;

  /// Whether the message named the person this is for — by username or by
  /// `@all`.
  ///
  /// Carried rather than recomputed because the caller that has to act on it
  /// is not always the one that could work it out. A push isolate under
  /// [NotificationLevel.mentions] has to drop everything that is not a
  /// mention, and it holds the plaintext for exactly as long as it takes to
  /// build one of these.
  final bool mentioned;

  const ChatNotice({
    required this.title,
    required this.body,
    this.mentioned = false,
  });

  /// What to show where the message itself has no text.
  ///
  /// An attachment-only message is not an empty one, and a notification with a
  /// blank body reads as a bug.
  static const attachmentPreview = 'Sent an attachment';

  static String preview(String text) =>
      text.isNotEmpty ? text : attachmentPreview;

  /// A message in a channel. [mentionable] is the set of names that count as
  /// "you" — being named is the one thing worth distinguishing from being in
  /// the room, and it is why this path holds the decrypted text at all.
  factory ChatNotice.channel({
    required String author,
    required String channel,
    required String text,
    Set<String> mentionable = const {},
    int unread = 1,
  }) {
    final mentioned = mentionsAnyOf(text, mentionable);
    final base = mentioned
        ? '$author mentioned you in #$channel'
        : '$author in #$channel';
    return ChatNotice(
      title: _counted(base, unread),
      body: preview(text),
      mentioned: mentioned,
    );
  }

  /// A direct message, on a server or on central. The sender is the whole of
  /// the context — there is no room to name.
  factory ChatNotice.direct({
    required String author,
    required String text,
    int unread = 1,
  }) {
    return ChatNotice(title: _counted(author, unread), body: preview(text));
  }

  /// How many are waiting, when it is more than the one being quoted. The
  /// count goes in the title rather than the body so the body stays the
  /// message — which is the part worth reading.
  static String _counted(String base, int unread) =>
      unread > 1 ? '$base ($unread)' : base;
}
