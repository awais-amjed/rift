import '../enums/message_origin.dart';
import 'attachment.dart';
import 'forwarded_message.dart';
import 'link_preview.dart';
import 'message_reaction.dart';
import 'panel_block.dart';
import 'poll.dart';

/// Over the helper budget and one job: the message model; its fields each carry
/// a comment on what they mean.
///
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
  /// are stored in the clear.
  final String? authorAvatarPath;

  final String text;

  /// Decrypted attachments carried in the message body (images, audio, files).
  /// Empty for a plain text message.
  final List<Attachment> attachments;

  /// The sender's preview of the first link, or null. Drawn as a card
  /// under the text; never fetched here.
  final LinkPreview? preview;

  /// Aggregated emoji reactions (NOT E2E — server-visible). Merged in
  /// separately from the message body via `list_reactions`.
  final List<MessageReaction> reactions;

  /// The id of the message this one answers, read out of the sealed body.
  ///
  /// The *reference*, not the message: what it points at is resolved against
  /// rows this client has already decrypted and verified, and is handed to the
  /// row separately. So a reply to something deleted, locked, or simply older
  /// than the loaded page is still a reply — it just has nothing to quote, and
  /// says so rather than quoting whatever the sender claimed was there.
  final String? replyToId;

  bool get isReply => replyToId != null;

  /// A message this sender carried in from another conversation, or null.
  ///
  /// Drawn inside *their* row as a quoted block, never as the original author
  /// posting here: the signature on this row is the forwarder's, and there is
  /// no second one to check. See [ForwardedMessage].
  final ForwardedMessage? forwarded;

  final DateTime sentAt;
  final bool isMine;

  /// Sent optimistically, not yet acknowledged by the server.
  final bool isPending;

  /// A pending row whose send failed on the way out, and which is waiting to
  /// be told to try again.
  ///
  /// Still [isPending] — it is no more sent than it was a moment ago — but no
  /// longer in flight, which is a different thing to say and a different thing
  /// to draw. Only ever set for a failure that could plausibly succeed on a
  /// retry (see `ErrorCode.isRetryable`); a refusal takes the row away instead,
  /// because a "try again" on something the server has already declined is a
  /// button that cannot work.
  final bool sendFailed;

  /// How much of a pending send's files have gone, from 0 to 1, while a big
  /// one uploads. Null otherwise — on every row from the server, and on a
  /// send whose files are small enough to go in one request.
  final double? uploadProgress;

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
  ///
  /// [sendFailed] is in the key for exactly that reason. "Not sent" is drawn in
  /// the header, and only the first row of a group has one — so a failed
  /// message tucking under the message before it would be silent about the one
  /// fact it exists to report.
  ///
  /// [replyToId] is in it for the third time over: the quote is drawn once,
  /// at the top of a group, so a reply tucked under an ordinary message would
  /// lose the line saying what it answers. Two replies to the *same* message
  /// still group, which is right — the quote above them covers both.
  ///
  /// [isPinned] is in it for the same reason again: the pin is drawn in the
  /// header, so a pinned message tucked under the one before it would be
  /// pinned with nothing to say so.
  String get groupKey => origin.isMember
      ? '$authorId:$isEncrypted:$isEphemeral:$sendFailed:'
            '${replyToId ?? ''}:$isPinned'
      : '${origin.name}:$authorName:$isPinned';

  /// When the author last edited this message, or null if never edited.
  /// Drives the "(edited)" marker.
  final DateTime? editedAt;

  bool get isEdited => editedAt != null;

  /// Who put this in the channel. [MessageOrigin.member] for everything a
  /// person sent.
  final MessageOrigin origin;

  /// A bot's panel, or null for every message that is not one (`messages.blocks`).
  ///
  /// When it is set, it *replaces* the body rather than sitting beside it: a
  /// panel's text lives in its blocks, and rendering `text` as well would show
  /// whatever the bot happened to put in the column twice or not at all.
  final Panel? panel;

  /// Whether the body was sealed on the way here.
  ///
  /// Kept separate from [origin] rather than derived from it. They agree today
  /// — only webhooks write in the clear — and they stop agreeing the moment bot
  /// commands land, where a member deliberately sends a plaintext message. The
  /// badge answers to this one; the attribution answers to [origin].
  final bool isEncrypted;

  /// Sent in the clear in a channel whose encryption was turned off, where
  /// every new message is. The header and the composer say so once for the
  /// whole channel, so the row does not repeat it (`MessageOriginBadge`).
  final bool inPlainChannel;

  /// A bot's reply that only this reader can see (`messages.ephemeral_for`).
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

  /// A poll: the sealed question and options under the server's rules, or null
  /// for every message that is not one. See [Poll.combine].
  final Poll? poll;

  /// When this message was pinned, or null if it is not. Server-visible, like
  /// a reaction: the server knows *that* it is pinned, never what it says.
  final DateTime? pinnedAt;

  bool get isPinned => pinnedAt != null;

  const ChatMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    this.authorAvatarPath,
    required this.sentAt,
    required this.isMine,
    this.attachments = const [],
    this.preview,
    this.reactions = const [],
    this.isPending = false,
    this.sendFailed = false,
    this.uploadProgress,
    this.sentAsId,
    this.editedAt,
    this.origin = MessageOrigin.member,
    this.panel,
    this.isEncrypted = true,
    this.inPlainChannel = false,
    this.isLocked = false,
    this.isEphemeral = false,
    this.replyToId,
    this.forwarded,
    this.poll,
    this.pinnedAt,
  });

  /// [clearPinned] unpins; a null [pinnedAt] leaves the pin as it is.
  ChatMessage copyWith({
    List<MessageReaction>? reactions,
    String? text,
    DateTime? editedAt,
    String? sentAsId,
    bool? sendFailed,
    double? uploadProgress,
    bool clearUploadProgress = false,
    DateTime? pinnedAt,
    bool clearPinned = false,
    bool? inPlainChannel,
  }) => ChatMessage(
    id: id,
    authorId: authorId,
    authorName: authorName,
    authorAvatarPath: authorAvatarPath,
    text: text ?? this.text,
    sentAt: sentAt,
    isMine: isMine,
    attachments: attachments,
    preview: preview,
    reactions: reactions ?? this.reactions,
    isPending: isPending,
    sendFailed: sendFailed ?? this.sendFailed,
    uploadProgress: clearUploadProgress
        ? null
        : uploadProgress ?? this.uploadProgress,
    sentAsId: sentAsId ?? this.sentAsId,
    editedAt: editedAt ?? this.editedAt,
    origin: origin,
    panel: panel,
    isEncrypted: isEncrypted,
    inPlainChannel: inPlainChannel ?? this.inPlainChannel,
    isLocked: isLocked,
    isEphemeral: isEphemeral,
    replyToId: replyToId,
    forwarded: forwarded,
    poll: poll,
    pinnedAt: clearPinned ? null : pinnedAt ?? this.pinnedAt,
  );
}
