part of 'channel_chat_cubit.dart';

/// Fetching and decrypting a channel's history. Envelopes are opened with the
/// key version they were sealed under; anything failing signature verification
/// is dropped rather than rendered.
mixin _ChannelChatHistoryMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;
  CryptoRepository get _crypto;
  Map<int, Uint8List> get _keys;

  /// Called with messages that just arrived live (not the initial backlog and
  /// not our own sends) so the hub can clear typing state and notify.
  void _onFreshIncoming(List<ChatMessage> incoming);


  Future<void> _fetchLatest(String channelId) async {
    final response = await _serverCubit.listChatMessages(
      channelId: channelId,
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.channelId != channelId) return;

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    // Rows arrive newest-first; decrypt then restore oldest→newest order.
    final decrypted = await _decryptRows(channelId, rows);
    emit(
      state.copyWith(
        messages: decrypted.reversed.toList(),
        hasMoreHistory: data['has_more'] as bool? ?? false,
      ),
    );
  }

  /// Catch up on rows newer than what we hold (doorbell / reconnect path).
  Future<void> _fetchAfterLatest() async {
    final channelId = state.channelId;
    if (channelId == null) return;

    final response = await _serverCubit.listChatMessages(
      channelId: channelId,
      afterId: ChatMessageOps.latestId(state.messages),
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.channelId != channelId) return;

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return;

    final incoming = await _decryptRows(channelId, rows); // oldest-first
    if (incoming.isEmpty) return;

    final result = ChatMessageOps.mergeIncoming(
      current: state.messages,
      incoming: incoming,
    );
    if (result.fresh.isEmpty) return;

    emit(state.copyWith(messages: result.merged));

    final freshIncoming = result.fresh.where((m) => !m.isMine).toList();
    if (freshIncoming.isNotEmpty) _onFreshIncoming(freshIncoming);
  }

  /// Scroll-up pagination: prepend the page before the oldest loaded row.
  Future<void> loadMoreHistory() async {
    final channelId = state.channelId;
    if (channelId == null ||
        !state.hasMoreHistory ||
        state.isLoadingMore ||
        state.messages.isEmpty) {
      return;
    }
    emit(state.copyWith(isLoadingMore: true));

    final response = await _serverCubit.listChatMessages(
      channelId: channelId,
      beforeId: ChatMessageOps.oldestId(state.messages),
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success || state.channelId != channelId) {
      emit(state.copyWith(isLoadingMore: false));
      return;
    }

    final data = response.data as Map<String, dynamic>;
    final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
    final older = await _decryptRows(channelId, rows); // newest-first page
    emit(
      state.copyWith(
        messages: [...older.reversed, ...state.messages],
        hasMoreHistory: data['has_more'] as bool? ?? false,
        isLoadingMore: false,
      ),
    );
  }

  /// Decrypt + verify a batch of envelope rows, preserving input order.
  /// Rows we can't decrypt (missing key version) or that fail verification
  /// are dropped — a forged or tampered message is never rendered.
  Future<List<ChatMessage>> _decryptRows(
    String channelId,
    List<Map<String, dynamic>> rows,
  ) async {
    final localUserId = _serverCubit.state.selectedServer?.user?.id;
    final result = <ChatMessage>[];

    for (final row in rows) {
      final keyVersion = row['key_version'] as int;
      final key = _keys[keyVersion];
      final senderKeyB64 = row['sender_public_key'] as String?;
      if (key == null || senderKeyB64 == null) continue;

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
}
