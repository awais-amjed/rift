part of 'channel_chat_cubit.dart';

/// Turning envelope rows into renderable messages.
///
/// Split out of `_ChannelChatHistoryMixin` because fetching a page and deciding
/// what a row *is* are two jobs, and only the second one carries the rule that
/// matters: three outcomes, and two of them used to share a line. See
/// ARCHITECTURE.md §4, *Three things a client can do with a row*.
mixin _ChannelChatRowsMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;
  CryptoRepository get _crypto;
  Map<int, Uint8List> get _keys;

  /// Turn envelope rows into renderable messages, preserving input order.
  ///
  /// Three outcomes, and keeping them apart is the whole job:
  ///
  ///   * **opened** — decrypted and signature-verified, or never sealed at all
  ///     (key_version 0, a webhook);
  ///   * **locked** — sealed under a key version this device does not hold.
  ///     Rendered as a placeholder. Nothing is wrong; nobody has wrapped for us
  ///     yet, and it will open when they do;
  ///   * **dropped** — the signature does not verify, or the sender's key is
  ///     gone so it cannot be verified at all. A forged or tampered message is
  ///     never rendered, and never hinted at either.
  ///
  /// The middle one used to share a line with the last, which is why a member
  /// waiting on a key opened a busy channel and found an empty room.
  Future<List<ChatMessage>> _decryptRows(
    String channelId,
    List<Map<String, dynamic>> rows,
  ) async {
    final localUserId = _serverCubit.state.selectedServer?.user?.id;
    final result = <ChatMessage>[];

    for (final row in rows) {
      final keyVersion = row['key_version'] as int;

      // Version 0 is a body that was never sealed — today, only a webhook
      // (migration 013). There is no key to look up and no signature to check,
      // so it must branch out before any of the envelope machinery below, which
      // would drop it for being unopenable and unsigned.
      //
      // Whether it can be *trusted* is not answered here and is not meant to
      // be: it is rendered with its origin shown, and the badge is what says
      // the server could read it. See BOTS.md §3.
      if (keyVersion == 0) {
        final plain = _plainRow(row);
        if (plain != null) result.add(plain);
        continue;
      }

      // No key to verify *against* — the sender's row is gone. That is a
      // verification failure like any other and stays dropped.
      final senderKeyB64 = row['sender_public_key'] as String?;
      if (senderKeyB64 == null) continue;

      // No key for this *version*: ordinary, temporary, and not the message's
      // fault. See [ChatMessage.isLocked] for why this must not share a branch
      // with a bad signature.
      final key = _keys[keyVersion];
      if (key == null) {
        result.add(_lockedRow(row, localUserId));
        continue;
      }

      try {
        final plaintext = await _crypto.openMessage(
          envelope: MessageEnvelope.fromJson(row),
          messageKey: key,
          senderPublicKey: CryptoRepository.fromBase64(senderKeyB64),
          contextId: channelId,
        );
        if (plaintext == null) {
          HelperMethods.printDebug(
            '[Chat] dropped message ${row['id']}: bad signature',
          );
          continue;
        }
        final body = MessageBody.decode(plaintext);
        result.add(
          ChatMessage(
            id: '${row['id']}',
            authorId: row['sender_id'] as String,
            authorName: row['sender_name'] as String? ?? 'Unknown',
            authorAvatarPath: row['sender_avatar_path'] as String?,
            text: body.text,
            attachments: body.attachments,
            sentAt: DateTime.parse(row['created_at'] as String),
            isMine: row['sender_id'] == localUserId,
            editedAt: DateTime.tryParse('${row['edited_at']}'),
            reactions: ReactionOps.fromRow(row),
          ),
        );
      } catch (e) {
        HelperMethods.printDebug('[Chat] dropped message ${row['id']}: $e');
      }
    }
    return result;
  }

  /// A message we can see but not open, rendered as its own kind of row.
  ///
  /// Everything here comes from columns the server already stores in the clear,
  /// so showing it reveals nothing a member without the key could not read off
  /// the table themselves. What it buys is a channel that looks like what it
  /// is: forty messages you cannot read yet, rather than an empty room.
  ChatMessage _lockedRow(Map<String, dynamic> row, String? localUserId) =>
      ChatMessage(
        id: '${row['id']}',
        authorId: row['sender_id'] as String? ?? '',
        authorName: row['sender_name'] as String? ?? 'Unknown',
        authorAvatarPath: row['sender_avatar_path'] as String?,
        text: '',
        sentAt: DateTime.parse(row['created_at'] as String),
        isMine: row['sender_id'] == localUserId,
        editedAt: DateTime.tryParse('${row['edited_at']}'),
        isLocked: true,
      );

  /// An unencrypted row, or null if it is not one this build understands.
  ///
  /// A version 0 row with no `origin_name` cannot happen under 013's
  /// constraints, so reaching that branch means either a newer server writing a
  /// shape this build has not learned yet — bot commands are the next one — or
  /// something wrong. Dropping it is the same answer either way, and quieter
  /// than rendering a message from nobody.
  ChatMessage? _plainRow(Map<String, dynamic> row) {
    final originName = row['origin_name'] as String?;
    if (originName == null) return null;
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
      origin: MessageOrigin.webhook,
      isEncrypted: false,
    );
  }
}
