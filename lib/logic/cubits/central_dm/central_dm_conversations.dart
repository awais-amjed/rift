part of 'central_dm_cubit.dart';

/// The central-DM conversation list: newest row per peer, resolved against the
/// public directory for handles and keys, with a decrypted preview.
mixin _CentralDmConversationsMixin on Cubit<CentralDmState> {
  CentralDmRepository get _repo;
  String? get _myUserId;
  Map<String, String> get _peerSigningKeys;
  Map<String, String> get _peerChatKeys;

  /// Fire OS notifications for newly-arrived messages across all conversations.
  void _notifyFromConversations(List<DmConversation> conversations);

  /// Implemented by the unread mixin.
  Map<String, int> _countUnread(List<Map<String, dynamic>> rows, String myId);
  void _readOpenConversation(Map<String, int> counts);

  /// Implemented by the history mixin.
  Future<ChatMessage?> _decryptRow(
    Map<String, dynamic> row, {
    required String peerId,
    required String peerHandle,
  });

  Future<void> refreshConversations() async {
    final myId = _myUserId;
    if (myId == null) return;
    emit(state.copyWith(conversationsLoading: true));

    final response = await _repo.listRecentMessages();
    if (isClosed) return;
    if (!response.success) {
      emit(state.copyWith(conversationsLoading: false));
      return;
    }

    // Newest-first scan → first row per peer is the latest envelope.
    final rows = (response.data as List).cast<Map<String, dynamic>>();
    final latestByPeer = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final peerId = row['sender_id'] == myId
          ? row['recipient_id'] as String
          : row['sender_id'] as String;
      latestByPeer.putIfAbsent(peerId, () => row);
    }

    // The same rows carry the unread counts — central has no notification
    // table, so this fetch is where a badge comes from.
    final unread = _countUnread(rows, myId);
    _readOpenConversation(unread);

    if (latestByPeer.isEmpty) {
      emit(
        state.copyWith(
          conversations: const [],
          conversationsLoading: false,
          unreadByPeer: const {},
        ),
      );
      return;
    }

    final profiles = await _loadProfiles(latestByPeer.keys.toList());
    if (isClosed) return;

    final conversations = <DmConversation>[];
    for (final entry in latestByPeer.entries) {
      final profile = profiles[entry.key];
      final handle = profile?['handle'] as String? ?? 'unknown';
      final preview = await _decryptRow(
        entry.value,
        peerId: entry.key,
        peerHandle: handle,
      );
      conversations.add(
        DmConversation(
          peerId: entry.key,
          peerName: handle,
          peerChatPublicKey: profile?['chat_public_key'] as String?,
          peerSigningPublicKey: profile?['signing_public_key'] as String?,
          lastMessage: preview,
        ),
      );
    }
    conversations.sort((a, b) {
      final aId = int.tryParse(a.lastMessage?.id ?? '0') ?? 0;
      final bId = int.tryParse(b.lastMessage?.id ?? '0') ?? 0;
      return bId.compareTo(aId);
    });

    emit(
      state.copyWith(
        conversations: conversations,
        conversationsLoading: false,
        unreadByPeer: unread,
      ),
    );
    _notifyFromConversations(conversations);
  }

  /// Fetch directory profiles and cache each peer's published keys, which the
  /// history mixin needs to derive DM keys and verify signatures.
  Future<Map<String, Map<String, dynamic>>> _loadProfiles(
    List<String> peerIds,
  ) async {
    final response = await _repo.getProfiles(peerIds);
    final profiles = <String, Map<String, dynamic>>{};
    if (!response.success) return profiles;

    for (final p in (response.data as List).cast<Map<String, dynamic>>()) {
      final id = p['id'] as String;
      profiles[id] = p;
      _peerSigningKeys[id] = p['signing_public_key'] as String;
      _peerChatKeys[id] = p['chat_public_key'] as String;
    }
    return profiles;
  }
}
