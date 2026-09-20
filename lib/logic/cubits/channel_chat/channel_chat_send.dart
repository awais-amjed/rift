part of 'channel_chat_cubit.dart';

/// Sending into a channel, and fetching attachment bytes back for rendering.
mixin _ChannelChatSendMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;
  VaultCubit get _vaultCubit;
  CryptoRepository get _crypto;
  Map<int, Uint8List> get _keys;
  int get _currentKeyVersion;

  /// Implemented by the cubit class, like [_ChatSweepMixin]'s copy — see the
  /// note in `channel_chat_ready.dart` for why it lives there rather than in a
  /// mixin of its own.
  void _ringKeySweepDoorbell();

  /// Sends that did not get out. On the class rather than here because the
  /// history mixin restores from it too (CODE_STYLE §5).
  Outbox get _outbox;

  int _pendingCounter = 0;

  /// Seal, sign, and send a message ([text] and/or [attachments]); shows an
  /// optimistic pending message until the server acknowledges. Attachments are
  /// encrypted + uploaded first.
  ///
  /// A failure takes one of two paths, and which one is the whole of
  /// [_failSend]: a server that answered "no" removes the row and says why, a
  /// server that did not answer at all keeps it for a retry.
  ///
  /// [inVoiceChannel] is the call the sender is sitting in, or null. Passed in
  /// rather than read from a cubit here: "I am in this call while I ask" is a
  /// fact about the person sending, and the alternative is this cubit knowing
  /// about LiveKit so it can ask on their behalf.
  ///
  /// [replyToId] is the message being answered. It is sealed into the body,
  /// never sent as a column, and the author it names is added to the
  /// mentions below so the reply rings — which is the only thing the server
  /// learns about it, and the same thing it learns from an `@`.
  Future<void> sendMessage(
    String text, {
    List<PendingAttachment> attachments = const [],
    PendingLinkPreview? preview,
    String? inVoiceChannel,
    String? replyToId,
    bool pingReplyTo = true,
  }) async {
    final channelId = state.channelId;
    final server = _serverCubit.state.selectedServer;
    final user = server?.user;
    final key = _keys[_currentKeyVersion];
    if (channelId == null ||
        server == null ||
        user == null ||
        key == null ||
        state.status != ChannelChatStatus.ready) {
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;

    // Resolved before the send, against rows already decrypted and verified:
    // a reference to something this client cannot see is one it has no
    // business asserting, so it goes out as an ordinary message instead.
    final answering = replyToId == null
        ? null
        : state.messages.where((m) => m.id == replyToId).firstOrNull;
    final replyId = answering?.id;

    // Decided once, here, before anything is sealed — because it decides
    // *whether* anything is sealed. Unrecognised slashes are not commands and
    // fall through to the ordinary encrypted path (see [BotCommands.parse]).
    final command = attachments.isEmpty
        ? BotCommands.parse(
            trimmed,
            // Only the bots this channel can reach — resolved when the channel
            // opened, with the channel, so a private one offers the bots seated
            // in it. One that cannot read the command must not turn the line
            // plaintext to say so: unparsed, it goes out sealed like any other
            // message.
            state.bots,
          )
        : null;

    final pendingId = 'pending-${_pendingCounter++}';
    // Held in a local as well as emitted: if this send fails it becomes the
    // row the outbox keeps, and by then the reader may have walked away from
    // the channel — so it cannot be read back out of state.
    final pending = ChatMessage(
      id: pendingId,
      authorId: user.id,
      authorName: user.displayName,
      text: trimmed,
      sentAt: DateTime.now(),
      isMine: true,
      isPending: true,
      // The badge has to be on the row from the moment it appears. This is the
      // one message whose *sender* chose to send it in the clear, and the send
      // is exactly when they want to see that confirmed — waiting for a reload
      // to admit it would be the worst timing available.
      isEncrypted: command == null,
      replyToId: replyId,
    );
    // Show the text immediately; attachments appear once uploaded.
    emit(state.copyWith(messages: [...state.messages, pending]));

    try {
      Future<APIResponse> uploadOne(Uint8List bytes) =>
          _serverCubit.uploadAttachment(scopePrefix: channelId, data: bytes);
      final uploaded = await ChatAttachmentUploader.uploadAll(
        pending: attachments,
        uploadOne: uploadOne,
      );
      final sentPreview = await ChatAttachmentUploader.uploadPreview(
        pending: preview,
        uploadOne: uploadOne,
      );
      if (state.channelId != channelId) return;

      final host = Uri.parse(server.supabaseUrl).host;
      final identity = await _vaultCubit.getIdentityForHost(
        host,
        serverId: server.id,
        version: server.keyVersion,
      );
      // A command is stored in the clear: the bot holds no channel key, so a
      // sealed one would be a message it could never open (BOTS.md §4). It is
      // still signed — the signature is over the same canonical payload, and
      // being readable is not a reason to be unattributable.
      final envelope = command != null
          ? await _crypto.signPlaintext(
              plaintext: trimmed,
              signingKeyPair: identity.keyPair,
              contextId: channelId,
            )
          : await _crypto.sealMessage(
              plaintext: MessageBody(
                text: trimmed,
                attachments: uploaded,
                preview: sentPreview,
                replyToId: replyId,
              ).encode(),
              messageKey: key,
              signingKeyPair: identity.keyPair,
              contextId: channelId,
              keyVersion: _currentKeyVersion,
            );

      // The one part of a message that travels in the clear. See
      // `ServerRepository.sendMessage` for what that costs and buys.
      //
      // Resolved by asking about the names this message says, rather than by
      // looking them up in a roster held in memory: past a thousand members
      // that roster was a truncation, so a mention of somebody far down the
      // alphabet silently pinged nobody. Scoped to the channel, because the
      // trigger strips an outsider anyway and not sending their id means it
      // never sits in the clear on a row at all. A failed lookup costs the
      // message its pings rather than its delivery — the right way round.
      final spoken = Mentions.namesIn(trimmed);
      final named = Mentions.resolve(
        trimmed,
        idsByUsername: Mentions.rosterOf(
          spoken.isEmpty
              ? const []
              : await _serverCubit.membersByUsernames(
                  spoken,
                  channelId: channelId,
                ),
        ),
        excludeUserId: user.id,
      );
      // The author of what is being answered, added to the same array an `@`
      // writes to. A reply is a message aimed at somebody, and this is the
      // column that exists for saying so without saying what was said. Their
      // own reply to themselves never rings, and the toggle is the reader's
      // choice to answer quietly.
      final mentioned = {
        ...named.userIds,
        if (pingReplyTo &&
            answering != null &&
            answering.authorId.isNotEmpty &&
            answering.authorId != user.id)
          answering.authorId,
      }.toList();

      // Before the message, not after: the bot polls for what it is addressed,
      // and a summon that lands second is a bot arriving to a call it was told
      // about a poll ago. Failure is ignored on purpose — an unsummoned bot
      // does not turn up, which somebody can see and ask again, and is not a
      // reason to lose the message that carried it.
      if (command != null && command.summonsBot && inVoiceChannel != null) {
        final summoned = await _serverCubit.setBotVoiceSummon(
          channelId: inVoiceChannel,
          botId: command.bot.id,
          summon: true,
        );
        // Then tell whoever is in that call to seal it a media key. A summon is
        // the one thing that puts a bot on `bots_missing` while the call is
        // already running, and every other path that seals runs on somebody
        // joining — so without this the bot waits for a member to rejoin a call
        // they are already sitting in.
        if (summoned.success) _ringKeySweepDoorbell();
      }

      final response = await _serverCubit.sendChatMessage(
        channelId: channelId,
        envelope: envelope.toJson(),
        mentions: mentioned,
        mentionsAll: named.all,
        toBot: command?.bot.id,
      );

      // After the message, not before: the bot is being told to stop, and it
      // should get the chance to say so — edit its panel, post a last line —
      // before the connection is taken away. Dropping the summon does that
      // taking away, which is the point: leaving does not depend on the bot
      // acting on a verb it advertised.
      if (command != null && command.dismissesBot && inVoiceChannel != null) {
        await _serverCubit.setBotVoiceSummon(
          channelId: inVoiceChannel,
          botId: command.bot.id,
          summon: false,
        );
      }
      if (state.channelId != channelId) return;

      if (!response.success) {
        _failSend(
          pending: pending,
          channelId: channelId,
          attachments: attachments,
          errorCode: response.errorCode,
          error: response.error ?? 'Failed to send message',
        );
        return;
      }

      final data = response.data as Map<String, dynamic>;
      emit(
        state.copyWith(
          messages: ChatMessageOps.replacePending(
            state.messages,
            pendingId: pendingId,
            acked: ChatMessage(
              id: '${data['id']}',
              authorId: user.id,
              authorName: user.displayName,
              text: trimmed,
              attachments: uploaded,
              preview: sentPreview,
              replyToId: replyId,
              sentAt: DateTime.parse(data['created_at'] as String),
              isMine: true,
              isEncrypted: command == null,
            ),
          ),
        ),
      );
    } on AttachmentUploadException catch (e) {
      HelperMethods.printDebug('[Chat] attachment upload failed: $e');
      _failSend(
        pending: pending,
        channelId: channelId,
        attachments: attachments,
        errorCode: e.errorCode,
        error: 'Failed to upload attachment',
      );
    } catch (e) {
      HelperMethods.printDebug('[Chat] send failed: $e');
      // No code to read, so no claim that a retry would help. An exception
      // that got this far is a bug in the send path rather than a network
      // that dropped, and those are the same next time.
      _failSend(
        pending: pending,
        channelId: channelId,
        attachments: attachments,
        errorCode: null,
        error: 'Failed to send message',
      );
    }
  }

  /// What happens to a pending row when the send did not land.
  ///
  /// Two outcomes, decided entirely by whether anything answered. A refusal —
  /// a quota, a policy, a channel you are no longer in — takes the row away
  /// and says why, because the same message sent again would be refused again
  /// and a retry button would be a lie. A connection that dropped keeps the
  /// row, marks it, and holds what a second attempt would need.
  ///
  /// Nothing is shown for the retryable case: the row itself now says "Not
  /// sent", right where the reader is already looking, and a toast on top of it
  /// is the same news twice.
  ///
  /// Emits only while this is still the open channel, but holds either way —
  /// somebody who clicked elsewhere while a send was failing should still find
  /// it waiting when they come back (`Outbox.restoreInto`).
  void _failSend({
    required ChatMessage pending,
    required String channelId,
    required List<PendingAttachment> attachments,
    required String? errorCode,
    required String error,
  }) {
    final open = state.channelId == channelId;
    if (!Outbox.canRetry(errorCode)) {
      if (open) {
        _removePending(pending.id);
        HelperMethods.showError(error: error);
      }
      return;
    }
    _outbox.hold(
      OutboxEntry(
        destination: channelId,
        row: pending.copyWith(sendFailed: true),
        attachments: attachments,
      ),
    );
    if (open) {
      emit(
        state.copyWith(
          messages: ChatMessageOps.markFailed(state.messages, pending.id),
        ),
      );
    }
  }

  /// Try one held send again — what tapping a "Not sent" row does.
  ///
  /// The row is taken out and re-sent from the bottom rather than resurrected
  /// in place: it is being sent *now*, so now is where it belongs in the
  /// conversation. [Outbox.take] is what makes a double-tap harmless.
  Future<void> retrySend(String pendingId) async {
    final entry = _outbox.take(pendingId);
    if (entry == null) return;
    emit(
      state.copyWith(
        messages: ChatMessageOps.removePending(state.messages, pendingId),
      ),
    );
    await sendMessage(
      entry.text,
      attachments: entry.attachments,
      replyToId: entry.row.replyToId,
    );
  }

  void _removePending(String pendingId) {
    emit(
      state.copyWith(
        messages: ChatMessageOps.removePending(state.messages, pendingId),
      ),
    );
  }

  /// Fetch + decrypt an attachment's bytes (cache-first) for rendering.
  Future<Uint8List?> loadAttachment(Attachment attachment) =>
      ChatAttachmentUploader.load(
        attachment: attachment,
        download: () => _serverCubit.downloadAttachment(
          path: attachment.storagePath,
          keyB64: attachment.keyB64,
          nonceB64: attachment.nonceB64,
        ),
      );
}
