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
        // Guarded like the sealed branch below, and for the reason that branch
        // has always been: **one row must never cost the channel.** A single
        // message with a shape this build did not expect used to throw out of
        // here and leave the room stuck on its spinner — no list, no error,
        // nothing to retry.
        try {
          final plain = await _plainRow(row, channelId, localUserId);
          if (plain != null) result.add(plain);
        } catch (e) {
          HelperMethods.printDebug('[Chat] dropped row ${row['id']}: $e');
        }
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
  /// A version 0 row with neither cannot happen under 013/015/016's rules, so
  /// reaching that branch means a newer server writing a shape this build has
  /// not learned. Dropping it is the same answer as anything else it cannot
  /// account for.
  Future<ChatMessage?> _plainRow(
    Map<String, dynamic> row,
    String channelId,
    String? localUserId,
  ) async {
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
        origin: MessageOrigin.webhook,
        isEncrypted: false,
      );
    }

    // Everything else at version 0 has a sender: a member's command, or a
    // bot's reply to one. Both carry a name, so both are verified — the branch
    // is about *attribution*, not about which feature wrote the row. A bot
    // that does not sign its replies has them dropped exactly like anybody
    // else who doesn't, which is the SDK contract stated once.
    final senderKeyB64 = row['sender_public_key'] as String?;
    if (senderKeyB64 == null) return null;
    final verified = await _crypto.verifyPlaintext(
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

    return ChatMessage(
      id: '${row['id']}',
      authorId: row['sender_id'] as String? ?? '',
      authorName: row['sender_name'] as String? ?? 'Unknown',
      authorAvatarPath: row['sender_avatar_path'] as String?,
      text: row['ciphertext'] as String? ?? '',
      sentAt: DateTime.parse(row['created_at'] as String),
      isMine: row['sender_id'] == localUserId,
      editedAt: DateTime.tryParse('${row['edited_at']}'),
      reactions: ReactionOps.fromRow(row),
      isEncrypted: false,
      isEphemeral: row['ephemeral_for'] != null,
    );
  }
}
