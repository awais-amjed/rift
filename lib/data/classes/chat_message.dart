import '../enums/message_origin.dart';
import 'attachment.dart';
import 'message_reaction.dart';

/// One chat message as the cubits hold it and the chat UI kit renders it.
///
/// For a member's message that means decrypted and signature-verified —
/// envelopes that fail verification never become a ChatMessage. A webhook's
/// message ([MessageOrigin.webhook]) was never sealed and has no signature to
/// check; it is the server's word that it arrived, and [isEncrypted] is what
/// tells the two apart. See BOTS.md §3.
class ChatMessage {
  final String id;

  /// The sender's user id, or the empty string for a message no member sent.
  /// Never a real person's id unless a real person really sent it.
  final String authorId;

  final String authorName;

  /// The author's avatar object name, or null for initials. Not E2E — avatars
  /// are stored in the clear (migration 014).
  final String? authorAvatarPath;

  final String text;

  /// Decrypted attachments carried in the message body (images, audio, files).
  /// Empty for a plain text message.
  final List<Attachment> attachments;

  /// Aggregated emoji reactions (NOT E2E — server-visible). Merged in
  /// separately from the message body via `list_reactions`.
  final List<MessageReaction> reactions;

  final DateTime sentAt;
  final bool isMine;

  /// Sent optimistically, not yet acknowledged by the server.
  final bool isPending;

  /// The local id this message carried while it was pending, if it was sent
  /// from this client and has since been acknowledged.
  ///
  /// Not part of the message — nothing is sent or stored with it. It exists so
  /// the row keeps its *widget* identity across the ack: the chat list keys
  /// rows by id, and the server's id is not the one the pending row was drawn
  /// under, so without this the acked row is a different row as far as Flutter
  /// is concerned. It gets rebuilt from scratch, which tears out whatever the
  /// pending row was in the middle of — on a fast server, that is your own
  /// message's entrance snapping to the end halfway through.
  final String? sentAsId;

  /// What the chat list should key this row by: stable from the moment you
  /// press enter to long after the server has answered.
  String get rowId => sentAsId ?? id;

  /// What makes two consecutive messages "the same speaker", so the second
  /// hides its header and tucks under the first.
  ///
  /// Not [authorId], which is what this used to be. A message no member sent
  /// has no author id — so two *different* webhooks posting one after the other
  /// both carried the empty string, grouped, and the second was drawn under the
  /// first one's name with no header and therefore **no badge**. The one thing
  /// the badge exists to prevent, produced by the grouping rule.
  ///
  /// [isEncrypted] is in the key for the same reason: a member's plaintext bot
  /// command must not tuck silently under the sealed message they sent a
  /// moment earlier. [isEphemeral] likewise — a bot's private reply grouping
  /// under its public one would hide the badge that says only you can see it,
  /// which is the whole thing that row has to communicate.
  String get groupKey => origin.isMember
      ? '$authorId:$isEncrypted:$isEphemeral'
      : '${origin.name}:$authorName';

  /// When the author last edited this message, or null if never edited.
  /// Drives the "(edited)" marker.
  final DateTime? editedAt;

  bool get isEdited => editedAt != null;

  /// Who put this in the channel. [MessageOrigin.member] for everything a
  /// person sent.
  final MessageOrigin origin;

  /// Whether the body was sealed on the way here.
  ///
  /// Kept separate from [origin] rather than derived from it. They agree today
  /// — only webhooks write in the clear — and they stop agreeing the moment bot
  /// commands land, where a member deliberately sends a plaintext message. The
  /// badge answers to this one; the attribution answers to [origin].
  final bool isEncrypted;

  /// A bot's reply that only this reader can see (migration 016).
  ///
  /// Enforced by `messages_select`, not by clients agreeing to hide it — so
  /// this flag is for *saying so*, not for keeping it. The row never reaches
  /// anybody else, and the badge exists because a message that looks like it
  /// is in the channel and is not would otherwise be the most confusing thing
  /// on the screen: you would answer it, and nobody would know what you meant.
  final bool isEphemeral;

  /// Sealed under a key version this device does not hold, so [text] is empty
  /// and there is nothing to render but the fact that it exists.
  ///
  /// This is **not** the same as a message that failed verification, and the
  /// difference is the whole point. A bad signature is somebody forging a
  /// message and is dropped on the floor, silently, for good. A missing key is
  /// the ordinary state of a member nobody has wrapped for yet — the message is
  /// real, its author is real, and it will open the moment a key arrives.
  /// Dropping those was what made a channel look empty when it was full.
  final bool isLocked;

  const ChatMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    this.authorAvatarPath,
    required this.sentAt,
    required this.isMine,
    this.attachments = const [],
    this.reactions = const [],
    this.isPending = false,
    this.sentAsId,
    this.editedAt,
    this.origin = MessageOrigin.member,
    this.isEncrypted = true,
    this.isLocked = false,
    this.isEphemeral = false,
  });

  ChatMessage copyWith({
    List<MessageReaction>? reactions,
    String? text,
    DateTime? editedAt,
    String? sentAsId,
  }) => ChatMessage(
    id: id,
    authorId: authorId,
    authorName: authorName,
    authorAvatarPath: authorAvatarPath,
    text: text ?? this.text,
    sentAt: sentAt,
    isMine: isMine,
    attachments: attachments,
    reactions: reactions ?? this.reactions,
    isPending: isPending,
    sentAsId: sentAsId ?? this.sentAsId,
    editedAt: editedAt ?? this.editedAt,
    origin: origin,
    isEncrypted: isEncrypted,
    isLocked: isLocked,
    isEphemeral: isEphemeral,
  );
}
