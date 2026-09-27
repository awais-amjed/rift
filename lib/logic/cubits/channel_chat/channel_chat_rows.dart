part of 'channel_chat_cubit.dart';

/// Over the cubit-part budget and one job: what a row becomes, and the three
/// outcomes are the reason it is one file.
///
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
  /// Names already asked about, so scrolling does not re-ask on every page.
  ///
  /// Holds names that resolved to nobody as well as names that resolved, which
  /// is the point: `@nobody` is exactly the token that would otherwise be
  /// looked up again on every scroll for as long as the message is on screen.
  MentionNameCache get _mentionCache;

  /// Implemented by [_ChannelChatPollsMixin]; public for the reason in
  /// CODE_STYLE §5.
  Future<void> refreshTalliesFor(List<ChatMessage> messages);

  Future<List<ChatMessage>> _decryptRows(
    String channelId,
    List<Map<String, dynamic>> rows,
  ) async {
    final localUserId = _serverCubit.state.selectedServer?.user?.id;
    final result = <ChatMessage>[];

    for (final row in rows) {
      final keyVersion = row['key_version'] as int;

      // Version 0 is a body that was never sealed — today, only a webhook.
      // There is no key to look up and no signature to check,
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
            preview: body.preview,
            replyToId: body.replyToId,
            forwarded: body.forwarded,
            sentAt: DateTime.parse(row['created_at'] as String),
            isMine: row['sender_id'] == localUserId,
            editedAt: DateTime.tryParse('${row['edited_at']}'),
            reactions: ReactionOps.fromRow(row),
            poll: PollOps.fromRow(row, body.poll),
            pinnedAt: PinOps.pinnedAtOf(row),
          ),
        );
      } catch (e) {
        HelperMethods.printDebug('[Chat] dropped message ${row['id']}: $e');
      }
    }
    // The names these rows say, resolved in the background — see
    // [_resolveMentionNames]. Not awaited: a message must render now, and a
    // mention nobody has resolved yet draws as the text somebody typed.
    unawaited(_resolveMentionNames(result));
    // And how the polls among them stand, the same way: a poll draws with no
    // counts for the moment it takes, rather than holding up the page.
    unawaited(refreshTalliesFor(result));
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
        pinnedAt: PinOps.pinnedAtOf(row),
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
  /// A version 0 row with neither cannot happen under the `messages` CHECKs, so
  /// reaching that branch means a newer server writing a shape this build has
  /// not learned. Dropping it is the same answer as anything else it cannot
  /// account for.
  Future<ChatMessage?> _plainRow(
    Map<String, dynamic> row,
    String channelId,
    String? localUserId,
  ) async {
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
      // A bot's panel. Parsed after the signature check like everything else
      // on this row: an interface drawn from an envelope nobody could verify
      // is an interface anybody could have sent.
      panel: Panel.tryParse(row['blocks']),
      pinnedAt: PinOps.pinnedAtOf(row),
    );
  }

  /// Resolve the `@names` [messages] contain to the display names they draw as.
  ///
  /// Fire-and-forget, and deliberately after the rows are built rather than
  /// before: a message renders the moment it is decrypted, and an unresolved
  /// mention draws as the plain text somebody typed until this lands — which is
  /// also exactly how it draws for a name belonging to nobody.
  ///
  /// Scoped to the channel, so a name belonging to somebody outside a private
  /// one resolves to nothing and is drawn as plain text. That is the same set
  /// `validate_message_mentions` keeps, so what lights up is what was
  /// delivered.
  Future<void> _resolveMentionNames(List<ChatMessage> messages) async {
    final channelId = state.channelId;
    if (channelId == null) return;

    final wanted = _mentionCache.unasked(
      messages.expand((message) => Mentions.namesIn(message.text)),
    );
    if (wanted.isEmpty) return;

    final found = await _serverCubit.membersByUsernames(
      wanted,
      channelId: channelId,
    );

    // The channel moved under us, so these answers are about the wrong room.
    if (isClosed || state.channelId != channelId) return;

    if (found.isEmpty) {
      // Nothing came back. That is either "nobody answers to these names" or a
      // lookup that failed, and the two are indistinguishable here — so let
      // them be asked again rather than leaving a name unresolvable for the
      // life of the channel because one request happened to fail.
      _mentionCache.forget(wanted);
      return;
    }

    _mentionCache.remember({
      for (final member in Mentions.among(found))
        member.username: member.displayName,
    });
    emit(state.copyWith(mentionNames: _mentionCache.names));
  }
}
