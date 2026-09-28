part of 'channel_chat_cubit.dart';

/// The copy of a channel this device keeps: drawing it the moment the channel
/// opens, and pruning copies of channels the server stops listing. Writing it
/// back is [SavedConversation]'s job; see [MessageCache] for why it is sealed
/// and when it is wiped.
///
/// A channel's keys come from the server, so its copy carries the keys it was
/// sealed under as well — without them the rows would open as a page of locks
/// until the keyring loaded, which is the wait this exists to remove. They sit
/// inside the same sealed file, so they are no more exposed than the seed that
/// can already unwrap them.
mixin _ChannelChatSavedMixin on Cubit<ChannelChatState>, _ChannelChatRowsMixin {
  VaultCubit get _vaultCubit;
  MessageCache get _messageCache;
  SavedConversation get _saved;

  /// Draw the saved copy of [channelId], if there is one. Returns before any
  /// network is touched; what the server says replaces it moments later.
  Future<void> _drawSaved(Server server, String channelId) async {
    final saved = await _saved.open(
      _vaultCubit.state.masterSeed,
      MessageCacheSlot.channel(
        supabaseUrl: server.supabaseUrl,
        serverId: server.id,
        channelId: channelId,
      ),
      rowsAfter: (afterId) => _savedRowsAfter(channelId, afterId),
    );
    if (saved == null || isClosed || state.channelId != channelId) return;

    try {
      final keys = <int, Uint8List>{
        for (final entry in (saved['keys'] as Map).entries)
          int.parse('${entry.key}'): CryptoRepository.fromBase64(
            entry.value as String,
          ),
      };
      final messages = await _openRows(
        channelId,
        SavedConversation.rowsOf(saved),
        keys,
      );
      // Only while nothing fresher has landed: the server answering first is
      // not something to paint over.
      if (isClosed ||
          state.channelId != channelId ||
          state.status != ChannelChatStatus.loading) {
        return;
      }
      emit(
        state.copyWith(
          messages: messages.reversed.toList(),
          botListeners: (saved['bot_listeners'] as List? ?? const [])
              .cast<String>(),
          showingSaved: true,
        ),
      );
    } catch (e) {
      HelperMethods.printDebug('[Chat] saved copy unreadable: $e');
    }
  }

  /// [channelId]'s rows after [afterId] — how this device's own messages
  /// reach its copy. See [SavedConversation.noteSent].
  Future<List<Map<String, dynamic>>> _savedRowsAfter(
    String channelId,
    int afterId,
  ) async {
    final response = await _serverCubit.listChatMessages(
      channelId: channelId,
      afterId: afterId,
      limit: ChatMessageOps.pageSize,
    );
    if (!response.success) return const [];
    final data = response.data as Map<String, dynamic>;
    return (data['messages'] as List).cast<Map<String, dynamic>>();
  }

  /// What a channel keeps beside its rows. Read at the moment of writing, so
  /// it is the channel being saved that answers.
  Map<String, dynamic> _savedExtras() => {
    'keys': {
      for (final entry in _keys.entries)
        '${entry.key}': CryptoRepository.toBase64(entry.value),
    },
    'bot_listeners': state.botListeners,
  };

  /// Without a key every sealed row would open as a lock, and a page of locks
  /// drawn only to be replaced by a spinner is worse than the spinner.
  bool _canSaveChannel() => _keys.isNotEmpty;

  /// The channel list [_pruneSaved] last ran against, so it runs when the
  /// list changes rather than on every server emission.
  String? _prunedFor;

  /// Called on every server emission; prunes only when the list moved.
  void _pruneSavedIfListChanged(Server? server) {
    // Not before the vault opens either, or the list would be marked done
    // without anything having been pruned against it.
    if (server == null || _vaultCubit.state.masterSeed == null) return;
    final textChannels = [
      for (final channel in server.channels)
        if (channel.hasMessages) channel.id,
    ]..sort();
    // An empty list is far more often one that has not loaded yet than a
    // server with no text channels left, and pruning against it would throw
    // away every copy the moment the app starts.
    if (textChannels.isEmpty) return;
    final signature = '${server.supabaseUrl}|${server.id}|$textChannels';
    if (signature == _prunedFor) return;
    _prunedFor = signature;
    unawaited(_pruneSaved(server));
  }

  /// Drop the copies of channels [server] no longer lists — deleted, or
  /// private ones this member was taken out of.
  Future<void> _pruneSaved(Server server) async {
    final seed = _vaultCubit.state.masterSeed;
    if (seed == null) return;
    await _messageCache.keepOnly(
      seed,
      MessageCacheSlot.serverScope(server.supabaseUrl, server.id),
      [
        for (final channel in server.channels)
          if (channel.hasMessages)
            MessageCacheSlot.channel(
              supabaseUrl: server.supabaseUrl,
              serverId: server.id,
              channelId: channel.id,
            ),
      ],
    );
  }
}
