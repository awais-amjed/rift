part of 'channel_chat_cubit.dart';

/// Sending into a channel, and fetching attachment bytes back for rendering.
mixin _ChannelChatSendMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;
  ServerMembersCubit get _membersCubit;
  VaultCubit get _vaultCubit;
  CryptoRepository get _crypto;
  Map<int, Uint8List> get _keys;
  int get _currentKeyVersion;
  void _ringDoorbell();

  int _pendingCounter = 0;

  /// Seal, sign, and send a message ([text] and/or [attachments]); shows an
  /// optimistic pending message until the server acknowledges. Attachments are
  /// encrypted + uploaded first; on any failure the pending message is removed
  /// and an error toast shown.
  /// Press something on a bot's panel.
  ///
  /// Signed but not sealed, exactly like the command that would have done the
  /// same job before panels existed — the bot holds no channel key, so a sealed
  /// press is one it could not open. The channel sees the panel change and not
  /// the press: `is_interaction` keeps the row out of everybody else's view
  /// (migration 029).
  ///
  /// Fire-and-forget, and deliberately without an optimistic anything. What
  /// the press *does* is entirely the bot's business — it may change the panel,
  /// or take a second, or decide not to — so a client guessing at the outcome
  /// would be guessing.
  Future<void> pressPanelAction(
    String messageId,
    String action,
    String? value,
  ) async {
    final channelId = state.channelId;
    final server = _serverCubit.state.selectedServer;
    final user = server?.user;
    if (channelId == null || server == null || user == null) return;

    // The panel's author is the bot to answer. Taken from the row rather than
    // from anything the block carried: a button that named its own recipient
    // would let one bot's panel address another's.
    String? botId;
    for (final message in state.messages) {
      if (message.id == messageId) botId = message.authorId;
    }
    final replyTo = int.tryParse(messageId);
    if (botId == null || botId.isEmpty || replyTo == null) return;

    // The *server* identity, which is what signs a message — the chat identity
    // is X25519 and seals one.
    final identity = await _vaultCubit.getIdentityForHost(
      Uri.parse(server.supabaseUrl).host,
      serverId: server.id,
      version: server.keyVersion,
    );

    // The body is the action id rather than empty: it is what a client without
    // panels would show, and what the bot reads if it ignores `action_id`.
    final envelope = await _crypto.signPlaintext(
      plaintext: action,
      signingKeyPair: identity.keyPair,
      contextId: channelId,
    );

    final response = await _serverCubit.sendPanelAction(
      channelId: channelId,
      envelope: envelope.toJson(),
      toBot: botId,
      replyTo: replyTo,
      actionId: action,
      actionValue: value,
    );
    if (!response.success) {
      HelperMethods.showError(error: response.error ?? 'That did not go');
    }
  }

  /// [inVoiceChannel] is the call the sender is sitting in, or null. Passed in
  /// rather than read from a cubit here: "I am in this call while I ask" is a
  /// fact about the person sending, and the alternative is this cubit knowing
  /// about LiveKit so it can ask on their behalf.
  Future<void> sendMessage(
    String text, {
    List<PendingAttachment> attachments = const [],
    String? inVoiceChannel,
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

    // Decided once, here, before anything is sealed — because it decides
    // *whether* anything is sealed. Unrecognised slashes are not commands and
    // fall through to the ordinary encrypted path (see [BotCommands.parse]).
    final command = attachments.isEmpty
        ? BotCommands.parse(
            trimmed,
            // Only the bots this channel can reach. One that cannot read the
            // command must not turn the line plaintext to say so: unparsed, it
            // goes out sealed like any other message.
            ChannelReach.botsIn(
              _membersCubit.state.members ?? const [],
              state.audience,
            ),
          )
        : null;

    final pendingId = 'pending-${_pendingCounter++}';
    // Show the text immediately; attachments appear once uploaded.
    emit(
      state.copyWith(
        messages: [
          ...state.messages,
          ChatMessage(
            id: pendingId,
            authorId: user.id,
            authorName: user.displayName,
            text: trimmed,
            sentAt: DateTime.now(),
            isMine: true,
            isPending: true,
            // The badge has to be on the row from the moment it appears. This
            // is the one message whose *sender* chose to send it in the clear,
            // and the send is exactly when they want to see that confirmed —
            // waiting for a reload to admit it would be the worst timing
            // available.
            isEncrypted: command == null,
          ),
        ],
      ),
    );

    try {
      final uploaded = await ChatAttachmentUploader.uploadAll(
        pending: attachments,
        uploadOne: (bytes) =>
            _serverCubit.uploadAttachment(scopePrefix: channelId, data: bytes),
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
              ).encode(),
              messageKey: key,
              signingKeyPair: identity.keyPair,
              contextId: channelId,
              keyVersion: _currentKeyVersion,
            );

      // The one part of a message that travels in the clear. See
      // `ServerRepository.sendMessage` for what that costs and buys.
      // Empty while the roster is still loading, which costs the message its
      // pings rather than its delivery — the right way round. The alternative
      // is blocking a send on a fetch only needed to decide whose phone buzzes.
      final named = Mentions.resolve(
        trimmed,
        idsByUsername: Mentions.rosterOf(
          _membersCubit.state.members ?? const [],
          // The trigger strips an outsider anyway; not sending their id means
          // it never sits in the clear on a row at all.
          audience: state.audience,
        ),
        excludeUserId: user.id,
      );

      // Before the message, not after: the bot polls for what it is addressed,
      // and a summon that lands second is a bot arriving to a call it was told
      // about a poll ago. Failure is ignored on purpose — an unsummoned bot
      // does not turn up, which somebody can see and ask again, and is not a
      // reason to lose the message that carried it.
      if (command != null && command.needsVoice && inVoiceChannel != null) {
        await _serverCubit.setBotVoiceSummon(
          channelId: inVoiceChannel,
          botId: command.bot.id,
          summon: true,
        );
      }

      final response = await _serverCubit.sendChatMessage(
        channelId: channelId,
        envelope: envelope.toJson(),
        mentions: named.userIds,
        mentionsAll: named.all,
        toBot: command?.bot.id,
      );
      if (state.channelId != channelId) return;

      if (!response.success) {
        _removePending(pendingId);
        HelperMethods.showError(
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
              sentAt: DateTime.parse(data['created_at'] as String),
              isMine: true,
              isEncrypted: command == null,
            ),
          ),
        ),
      );
      _ringDoorbell();
    } on AttachmentUploadException catch (e) {
      HelperMethods.printDebug('[Chat] attachment upload failed: $e');
      if (state.channelId == channelId) {
        _removePending(pendingId);
        HelperMethods.showError(error: 'Failed to upload attachment');
      }
    } catch (e) {
      HelperMethods.printDebug('[Chat] send failed: $e');
      if (state.channelId == channelId) {
        _removePending(pendingId);
        HelperMethods.showError(error: 'Failed to send message');
      }
    }
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
