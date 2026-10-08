part of 'channel_chat_cubit.dart';

/// Polls in the open channel: posting one, voting, ending it, and keeping the
/// counts current.
///
/// A poll is two halves. Its question and options are sealed in the body
/// like any message; its rules — how many options, one pick or several, when
/// it closes — are on the row in the clear, because the server enforces them.
/// Votes are counted by the server and read back as totals: nothing here, or
/// anywhere a member can reach, learns who voted for what.
mixin _ChannelChatPollsMixin on Cubit<ChannelChatState> {
  SessionRepository get _session;
  ChannelMessagesApi get _channelMessages;
  PinsPollsApi get _pinsPolls;
  VaultCubit get _vaultCubit;
  CryptoRepository get _crypto;
  Map<int, Uint8List> get _keys;
  int get _currentKeyVersion;
  bool get _plainChannel;

  Future<void> refreshMessage(String messageId);

  /// Post a poll asking [body], open for [duration].
  ///
  /// Not drawn until the server has it. A pending row is how an ordinary
  /// message appears at once, and it works because the text is the whole of
  /// it; a poll is also its rules, and the closing time the server settles on
  /// is the one to show.
  Future<bool> sendPoll(
    PollBody body, {
    required bool multiple,
    required Duration duration,
  }) async {
    final channelId = state.channelId;
    final server = _session.selectedServer;
    final user = server?.user;
    final key = _keys[_currentKeyVersion];
    final plain = _plainChannel;
    if (channelId == null ||
        server == null ||
        user == null ||
        (key == null && !plain) ||
        state.status != ChannelChatStatus.ready) {
      return false;
    }

    try {
      final identity = await _vaultCubit.getIdentityForHost(
        Uri.parse(server.supabaseUrl).host,
        serverId: server.id,
        version: server.keyVersion,
      );
      final sealedBody = MessageBody(poll: body).encode();
      final envelope = plain
          ? await _crypto.signPlaintext(
              plaintext: sealedBody,
              signingKeyPair: identity.keyPair,
              contextId: channelId,
            )
          : await _crypto.sealMessage(
              plaintext: sealedBody,
              messageKey: key!,
              signingKeyPair: identity.keyPair,
              contextId: channelId,
              keyVersion: _currentKeyVersion,
            );
      final rules = PollRules(
        options: body.options.length,
        multiple: multiple,
        closesAt: DateTime.now().add(duration),
      );
      final response = await _channelMessages.sendChatMessage(
        channelId: channelId,
        envelope: envelope.toJson(),
        poll: rules.toJson(),
      );
      if (!response.success) {
        emit(
          state.copyWith(
            notice: Notice.error(response.error ?? 'Could not post poll'),
          ),
        );
        return false;
      }
      if (state.channelId != channelId) return true;

      final data = response.data as Map<String, dynamic>;
      final posted = ChatMessage(
        id: '${data['id']}',
        authorId: user.id,
        authorName: user.displayName,
        text: '',
        sentAt: DateTime.parse(data['created_at'] as String),
        isMine: true,
        isEncrypted: !plain,
        inPlainChannel: plain,
        poll: PollOps.fromRow(data, body),
      );
      emit(
        state.copyWith(
          messages: ChatMessageOps.mergeIncoming(
            current: state.messages,
            incoming: [posted],
          ).merged,
          pollTallies: {
            ...state.pollTallies,
            posted.id: PollTally.empty(body.options.length),
          },
        ),
      );
      return true;
    } catch (e) {
      HelperMethods.printDebug('[Chat] poll send failed: $e');
      emit(state.copyWith(notice: Notice.error('Could not post poll')));
      return false;
    }
  }

  /// Tap [option] on the poll in [messageId]: vote for it, move the vote to
  /// it, or take it back — whichever that tap means for this poll (see
  /// [PollOps.ballotAfterTap]).
  Future<void> vote(String messageId, int option) async {
    final channelId = state.channelId;
    final id = int.tryParse(messageId);
    final poll = state.messages
        .where((m) => m.id == messageId)
        .firstOrNull
        ?.poll;
    if (channelId == null || id == null || poll == null) return;

    final ballot = PollOps.ballotAfterTap(
      multiple: poll.multiple,
      mine: state.pollTallies[messageId]?.mine ?? const {},
      option: option,
    );
    final response = await _pinsPolls.votePoll(messageId: id, options: ballot);
    if (!response.success) {
      emit(
        state.copyWith(
          notice: Notice.error(
            PollOps.errorFor(response.error) ?? 'Could not vote',
          ),
        ),
      );
      // A refusal for being closed means the row is out of date; read it.
      unawaited(refreshMessage(messageId));
      return;
    }
    final tally = PollTally.fromJson(response.data);
    if (tally == null || state.channelId != channelId) return;
    emit(state.copyWith(pollTallies: {...state.pollTallies, messageId: tally}));
  }

  /// End the poll in [messageId] now. Its author only.
  Future<void> closePoll(String messageId) async {
    final id = int.tryParse(messageId);
    if (id == null) return;
    final response = await _pinsPolls.closePoll(messageId: id);
    if (!response.success) {
      emit(
        state.copyWith(
          notice: Notice.error(
            PollOps.errorFor(response.error) ?? 'Could not end the poll',
          ),
        ),
      );
      return;
    }
    await refreshMessage(messageId);
  }

  /// Ask how the polls among [messages] stand, and keep the answer.
  ///
  /// Cubit-internal; public only because [_ChannelChatRowsMixin] calls it
  /// (CODE_STYLE §5). Called with every batch of rows decrypted, so it covers
  /// a page of history, a catch-up and a single re-read alike.
  Future<void> refreshTalliesFor(List<ChatMessage> messages) async {
    final channelId = state.channelId;
    final ids = PollOps.pollIds(messages);
    if (channelId == null || ids.isEmpty) return;
    final response = await _pinsPolls.pollTallies(messageIds: ids);
    if (!response.success || isClosed || state.channelId != channelId) return;
    final answered =
        (response.data as Map<String, dynamic>)['tallies']
            as Map<String, dynamic>;
    emit(
      state.copyWith(
        pollTallies: PollOps.mergeTallies(state.pollTallies, answered),
      ),
    );
  }

  /// Somebody voted. The ring carries the poll's id and nothing about who.
  void _onPollDoorbell(Map<String, dynamic> payload) {
    if (isClosed) return;
    final messageId = BroadcastPayload.stringOf(payload, 'message_id');
    final poll = state.messages.where((m) => m.id == messageId).firstOrNull;
    if (poll != null) unawaited(refreshTalliesFor([poll]));
  }
}
