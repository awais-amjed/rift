part of 'dm_cubit.dart';

/// The list of conversations with their decrypted previews, a page at a time.
///
/// It used to be the whole list. `dm_conversations()` returned one row per
/// person you had ever messaged on this server, and it was refetched on every
/// server switch and every incoming DM — so somebody who had spoken to two
/// hundred people paid two hundred preview decryptions to draw the dozen tiles
/// that fit on screen, and paid them again the next time anybody said hello.
///
/// Nothing was ever missing from it: a JSONB scalar is not subject to the
/// 1000-row response cap, which is why it was built that way. It only grew,
/// which is why it outlived the reads that could truncate and is being fixed
/// last. `dm_conversations(p_limit, p_before)` gives it the
/// cursor central's list already had.
mixin _DmConversationsMixin on Cubit<DmState> {
  SessionRepository get _session;
  DmsApi get _dms;
  Map<String, String> get _dmKeySources;
  Future<Uint8List?> _dmKeyFor(String peerId, String? peerChatKey);

  /// Implemented by the history mixin.
  Future<bool> _fetchLatest(String peerId);

  /// Fire OS notifications for newly-arrived messages across all conversations.
  void _notifyFromConversations(List<DmConversation> conversations);
  Future<ChatMessage?> _decryptDmRow(
    Map<String, dynamic> row, {
    required String peerId,
    required String peerName,
    required String? peerChatKey,
    required String? peerSigningKey,
  });

  String? get _localUserId => _session.selectedServer?.user?.id;

  /// Guards a scroll that asks again before the last answer has landed.
  ///
  /// Cubit-internal rather than state: nothing on screen draws it, and the only
  /// question the list needs answered is [DmState.hasMoreConversations].
  bool _loadingMoreConversations = false;

  /// Reload from the top. Runs on open, on every incoming message and when
  /// the inbox rejoins after a dropped connection, so it deliberately
  /// re-reads only the first page — a conversation that has just been spoken
  /// in is at the top of it by definition.
  Future<void> refreshConversations() async {
    if (_localUserId == null) return;
    final openPeer = state.openPeerId;
    final openKeyBefore = openPeer == null ? null : _dmKeySources[openPeer];
    emit(state.copyWith(conversationsLoading: true));

    final page = await _fetchConversations();
    if (isClosed) return;
    if (page == null) {
      emit(
        state.copyWith(conversationsLoading: false, conversationsFailed: true),
      );
      return;
    }

    // Everything below the first page is dropped rather than merged: those rows
    // may have moved above it since, and reconciling two reads of a list that
    // reorders itself is how a conversation ends up drawn twice.
    emit(
      state.copyWith(
        conversations: page.conversations,
        conversationsLoading: false,
        conversationsFailed: false,
        hasMoreConversations: page.hasMore,
      ),
    );
    _notifyFromConversations(page.conversations);
    if (openPeer != null && openKeyBefore != null) {
      await _rekeyIfChanged(openPeer, openKeyBefore);
    }
  }

  /// The open conversation's peer published a new chat key: work out the new
  /// DM key and read the page again under it. What they send from now on is
  /// sealed to it, and what was sealed to the old one shows as locked rather
  /// than silently failing — the chip and the line in the conversation say
  /// why (`KeyWatch`).
  Future<void> _rekeyIfChanged(String peerId, String keyBefore) async {
    final listed = state.conversations
        .where((c) => c.peerId == peerId)
        .firstOrNull
        ?.peerChatPublicKey;
    if (listed == null || listed == keyBefore) return;
    await _dmKeyFor(peerId, listed);
    if (isClosed || state.openPeerId != peerId) return;
    await _fetchLatest(peerId);
  }

  /// Append the next page — what the list asks for as it is scrolled.
  ///
  /// Safe to call on every scroll frame: a call while one is in flight, or
  /// after the end, is a no-op.
  Future<void> loadMoreConversations() async {
    if (_loadingMoreConversations || !state.hasMoreConversations) return;
    final last = state.conversations.lastOrNull?.lastMessage?.id;
    final before = int.tryParse(last ?? '');
    if (before == null) return;

    _loadingMoreConversations = true;
    final page = await _fetchConversations(before: before);
    _loadingMoreConversations = false;
    if (isClosed || page == null) return;

    emit(
      state.copyWith(
        conversations: [...state.conversations, ...page.conversations],
        hasMoreConversations: page.hasMore,
      ),
    );
    // Not notified from here. A page fetched by scrolling is older than
    // everything already on screen, so anything in it that could interrupt has
    // long since been decided about.
  }

  /// One page, decrypted. Null when the request failed.
  Future<({List<DmConversation> conversations, bool hasMore})?>
  _fetchConversations({int? before}) async {
    final response = await _dms.listDmConversations(before: before);
    if (isClosed || !response.success) return null;

    final data = response.data as Map<String, dynamic>;
    final rows = (data['conversations'] as List? ?? const [])
        .cast<Map<String, dynamic>>();

    final conversations = await _conversationsFrom(rows);
    if (conversations == null) return null;
    return (conversations: conversations, hasMore: data['has_more'] == true);
  }

  /// Rows in the `dm_conversations` shape, previews decrypted. The requests
  /// list comes in the same shape and goes through here too. Null when the
  /// cubit closed partway.
  Future<List<DmConversation>?> _conversationsFrom(
    List<Map<String, dynamic>> rows,
  ) async {
    final conversations = <DmConversation>[];
    for (final row in rows) {
      final peerId = row['peer_id'] as String;
      final peerName = row['peer_name'] as String? ?? 'Unknown';
      final peerChatKey = row['peer_chat_public_key'] as String?;
      final peerSigningKey = row['peer_public_key'] as String?;

      ChatMessage? preview;
      final last = row['last_message'] as Map<String, dynamic>?;
      if (last != null) {
        preview = await _decryptDmRow(
          last,
          peerId: peerId,
          peerName: peerName,
          peerChatKey: peerChatKey,
          peerSigningKey: peerSigningKey,
        );
      }
      conversations.add(
        DmConversation(
          peerId: peerId,
          peerName: peerName,
          peerChatPublicKey: peerChatKey,
          peerSigningPublicKey: peerSigningKey,
          peerAvatarPath: row['peer_avatar_path'] as String?,
          lastMessage: preview,
        ),
      );
    }
    if (isClosed) return null;
    return conversations;
  }
}
