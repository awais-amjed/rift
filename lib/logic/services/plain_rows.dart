import 'package:rift_crypto/rift_crypto.dart';

import '../../data/classes/chat_message.dart';
import '../../data/classes/message_body.dart';
import '../../data/classes/panel_block.dart';
import '../../data/enums/message_origin.dart';
import '../helper_methods.dart';
import 'pin_ops.dart';
import 'poll_ops.dart';
import 'reaction_ops.dart';

/// A row whose body was never sealed, opened: the open channel's page, and a
/// bot's player read from a channel that is not open (`CallPanelsCubit`).
class PlainRows {
  const PlainRows._();

  /// An unencrypted row, or null if it should not be shown.
  ///
  /// Two shapes arrive here and they are checked differently, which is the
  /// whole point:
  ///
  ///   * **A webhook's message** (`origin_name`) has no signer — GitHub holds
  ///     no Rift key — so there is nothing to verify. It is safe *because* it
  ///     is never attributed to a person: the badge says an integration posted
  ///     it, and no name in the room is put behind it.
  ///   * **A member's `/` command** (`to_bot`) is attributed to somebody, in a
  ///     room full of people. So it is verified exactly like a sealed message,
  ///     and an unverifiable one is dropped in the same silence. Being readable
  ///     is not a reason to let the server put words under a name.
  ///
  /// A version 0 row with neither cannot happen under the `messages` CHECKs, so
  /// reaching that branch means a newer server writing a shape this build has
  /// not learned. Dropping it is the same answer as anything else it cannot
  /// account for.
  static Future<ChatMessage?> open(
    CryptoRepository crypto,
    Map<String, dynamic> row, {
    required String channelId,
    required String? localUserId,
    required bool plainChannel,
  }) async {
    // A press is not a message, including for the person who pressed. The
    // policy already keeps it from everybody else; this is the
    // half that keeps the presser's own view from filling with the log a panel
    // exists to replace.
    if (row['is_interaction'] == true) return null;

    final originName = row['origin_name'] as String?;
    if (originName != null) {
      return ChatMessage(
        id: '${row['id']}',
        // Not a person, so not a person's id. Nothing may resolve this to a
        // profile, open a DM with it, or treat it as a member.
        authorId: '',
        authorName: originName,
        text: row['ciphertext'] as String? ?? '',
        sentAt: DateTime.parse(row['created_at'] as String),
        isMine: false,
        editedAt: DateTime.tryParse('${row['edited_at']}'),
        reactions: ReactionOps.fromRow(row),
        origin: MessageOrigin.fromRow(row),
        isEncrypted: false,
        pinnedAt: PinOps.pinnedAtOf(row),
      );
    }

    // Everything else at version 0 has a sender: a member's command, or a
    // bot's reply to one. Both carry a name, so both are verified — the branch
    // is about *attribution*, not about which feature wrote the row. A bot
    // that does not sign its replies has them dropped exactly like anybody
    // else who doesn't, which is the SDK contract stated once.
    final senderKeyB64 = row['sender_public_key'] as String?;
    if (senderKeyB64 == null) return null;
    final verified = await crypto.verifyPlaintext(
      envelope: MessageEnvelope.fromJson(row),
      senderPublicKey: CryptoRepository.fromBase64(senderKeyB64),
      contextId: channelId,
    );
    if (!verified) {
      HelperMethods.printDebug(
        '[Chat] dropped command ${row['id']}: bad signature',
      );
      return null;
    }

    // The same body a sealed message carries, when it came from a channel
    // whose encryption is off — files, a reply, a preview, a poll. A command
    // is bare text, which reads back as itself.
    final body = MessageBody.decode(row['ciphertext'] as String? ?? '');
    return ChatMessage(
      id: '${row['id']}',
      authorId: row['sender_id'] as String? ?? '',
      authorName: row['sender_name'] as String? ?? 'Unknown',
      authorAvatarPath: row['sender_avatar_path'] as String?,
      text: body.text,
      attachments: body.attachments,
      preview: body.preview,
      replyToId: body.replyToId,
      forwarded: body.forwarded,
      poll: PollOps.fromRow(row, body.poll),
      sentAt: DateTime.parse(row['created_at'] as String),
      isMine: row['sender_id'] == localUserId,
      editedAt: DateTime.tryParse('${row['edited_at']}'),
      reactions: ReactionOps.fromRow(row),
      isEncrypted: false,
      inPlainChannel: plainChannel,
      isEphemeral: row['ephemeral_for'] != null,
      isCommand: row['to_bot'] != null,
      // A bot's panel. Parsed after the signature check like everything else
      // on this row: an interface drawn from an envelope nobody could verify
      // is an interface anybody could have sent.
      panel: Panel.tryParse(row['blocks'], channelId: channelId),
      pinnedAt: PinOps.pinnedAtOf(row),
    );
  }
}
