part of 'central_dm_cubit.dart';

/// The central-DM conversation list: one page at a time, each row carrying
/// everything it draws.
///
/// It used to be derived here. `listRecentMessages(limit: 1000)` pulled the
/// last thousand envelopes and this file scanned them twice — once for the
/// newest row per peer, once for the unread counts — while the read cursors and
/// the notification levels were fetched whole beside them. Three things were
/// wrong with that, and only the first is about bandwidth: a thousand envelopes
/// crossed the wire to draw a dozen rows; past a thousand *total* messages an
/// old conversation dropped off the list silently, and since those same rows
/// were where the badges came from, its badge went with it; and there was no
/// cursor with which to ask for the next page, because the list was a
/// by-product rather than a query.
///
/// `dm_conversations(p_limit, p_before)` answers all of
/// it, which is what the self-hosted tier already did.
mixin _CentralDmConversationsMixin on Cubit<CentralDmState> {
  CentralDmRepository get _repo;
  String? get _myUserId;
  Map<String, String> get _peerSigningKeys;
  Map<String, String> get _peerChatKeys;

  /// Fire OS notifications for newly-arrived messages across all conversations.
  /// [partial] for a read of one conversation, which announces nothing until
  /// a whole list has been seen.
  void _notifyFromConversations(
    List<DmConversation> conversations, {
    bool partial,
  });

  /// Implemented by the unread mixin.
  void _rememberCursors(
    Map<String, int> latestInbound,
    Map<String, int> unread, {
    bool merge,
  });
  void _readOpenConversation(Map<String, int> counts);

  /// Implemented by the history mixin.
  Future<ChatMessage?> _decryptRow(
    Map<String, dynamic> row, {
    required String peerId,
    required String peerHandle,
  });

  /// Whether another page of conversations exists, and where it resumes.
  ///
  /// Cubit-internal rather than state, because nothing on screen renders them —
  /// the list asks for more by scrolling, and the only question it needs
  /// answered is [CentralDmState.hasMoreConversations].
  bool _loadingMoreConversations = false;

  /// Where the next page starts: the newest message id of the last row
  /// listed, as central sent it. Not read from the decrypted preview, which
  /// is null for a row whose newest message was dropped, and that ended
  /// paging there with the spinner still turning.
  int? _conversationsCursor;

  /// Counts reads from the top. A page asked for before one is from the list
  /// as it was, and appended after it, it could skip a page or list somebody
  /// twice.
  int _conversationReads = 0;

  /// Whether a read from the top has come back, either way, since this
  /// account was set up. [listed] waits on it.
  bool _conversationsListed = false;

  /// Forget where the list had got to — on teardown, with the account.
  void _resetConversationReads() {
    _conversationsCursor = null;
    _conversationReads++;
    _conversationsListed = false;
    _loadingMoreConversations = false;
  }

  /// The first page of the list has come in, or has been tried — what a
  /// press on a notification waits for on a cold start, when the list it
  /// opens the person from is still empty.
  Future<void> listed() async {
    if (_conversationsListed) return;
    await stream
        .firstWhere((_) => _conversationsListed)
        .timeout(const Duration(seconds: 10), onTimeout: () => state);
  }

  /// Reload from the top. Runs on open and on every incoming message, so it
  /// deliberately re-reads only the first page — a conversation that has just
  /// been spoken in is at the top of it by definition.
  Future<void> refreshConversations() async {
    final myId = _myUserId;
    if (myId == null) return;
    final read = ++_conversationReads;
    emit(state.copyWith(conversationsLoading: true));

    final page = await _fetchConversations();
    if (isClosed) return;
    // A later read is on its way and answers for the list — or the account
    // this was read for has gone.
    if (read != _conversationReads) return;
    _conversationsListed = true;
    if (page == null) {
      emit(state.copyWith(conversationsLoading: false));
      return;
    }
    _conversationsCursor = page.cursor;

    // Everything below the first page is dropped rather than kept: the rows in
    // it may have moved above it since, and merging two reads of a list that
    // reorders itself is how a conversation ends up drawn twice.
    _readOpenConversation(page.unread);
    emit(
      state.copyWith(
        conversations: page.conversations,
        conversationsLoading: false,
        hasMoreConversations: page.hasMore,
        unreadByPeer: page.unread,
        levelsByPeer: page.levels,
      ),
    );
    _notifyFromConversations(page.conversations);
  }

  /// Re-read the one conversation with [peerId], and put it back where its
  /// newest message belongs.
  ///
  /// What an arriving DM costs now. It used to cost [refreshConversations],
  /// which rebuilds the first page out of every message the account has
  /// exchanged in thirty days — on every device the account is signed in on,
  /// for every message.
  Future<void> refreshConversation(String peerId) async {
    if (_myUserId == null) return;
    final page = await _fetchConversations(peer: peerId);
    if (isClosed || page == null) return;

    final updated = page.conversations.firstOrNull;
    final unread = {...state.unreadByPeer}
      ..remove(peerId)
      ..addAll(page.unread);
    final levels = {...state.levelsByPeer}
      ..remove(peerId)
      ..addAll(page.levels);
    _readOpenConversation(unread);
    emit(
      state.copyWith(
        conversations: ConversationSplice.apply(
          state.conversations,
          peerId: peerId,
          updated: updated,
        ),
        unreadByPeer: unread,
        levelsByPeer: levels,
      ),
    );
    if (updated != null) _notifyFromConversations([updated], partial: true);
  }

  /// Append the next page — what the list asks for as it is scrolled.
  ///
  /// Safe to call on every scroll frame: a call while one is in flight, or
  /// after the end, is a no-op.
  Future<void> loadMoreConversations() async {
    if (_loadingMoreConversations || !state.hasMoreConversations) return;
    final before = _conversationsCursor;
    if (before == null) return;

    final read = _conversationReads;
    _loadingMoreConversations = true;
    final ({
      List<DmConversation> conversations,
      Map<String, int> unread,
      Map<String, NotificationLevel> levels,
      bool hasMore,
      int? cursor,
    })?
    page;
    try {
      page = await _fetchConversations(before: before);
    } finally {
      if (read == _conversationReads) _loadingMoreConversations = false;
    }
    if (isClosed || page == null || read != _conversationReads) return;

    _conversationsCursor = page.cursor;
    emit(
      state.copyWith(
        conversations: [...state.conversations, ...page.conversations],
        hasMoreConversations: page.hasMore,
        unreadByPeer: {...state.unreadByPeer, ...page.unread},
        levelsByPeer: {...state.levelsByPeer, ...page.levels},
      ),
    );
  }

  /// One page, decrypted and indexed. Null when the request failed.
  Future<
    ({
      List<DmConversation> conversations,
      Map<String, int> unread,
      Map<String, NotificationLevel> levels,
      bool hasMore,
      int? cursor,
    })?
  >
  _fetchConversations({int? before, String? peer}) async {
    final myId = _myUserId;
    final response = await _repo.listConversations(before: before, peer: peer);
    if (isClosed || !response.success || _myUserId != myId) return null;

    final data = response.data as Map<String, dynamic>;
    final rows = (data['conversations'] as List? ?? const [])
        .cast<Map<String, dynamic>>();

    final conversations = <DmConversation>[];
    final unread = <String, int>{};
    final levels = <String, NotificationLevel>{};
    final latestInbound = <String, int>{};

    for (final row in rows) {
      final peerId = row['peer_id'] as String;
      final handle = row['handle'] as String? ?? 'unknown';

      // Cached before the preview is decrypted: the history mixin derives the
      // DM key and verifies signatures from these, and the preview itself is
      // the first thing that needs them.
      final chatKey = row['chat_public_key'] as String?;
      final signingKey = row['signing_public_key'] as String?;
      if (chatKey != null) _peerChatKeys[peerId] = chatKey;
      if (signingKey != null) _peerSigningKeys[peerId] = signingKey;

      final count = (row['unread'] as num?)?.toInt() ?? 0;
      if (count > 0) unread[peerId] = count;
      latestInbound[peerId] = (row['latest_inbound'] as num?)?.toInt() ?? 0;

      // Null is "the default", which is the client's word rather than the
      // database's — so an absent level is left absent rather than written in.
      final level = row['level'];
      if (level != null) {
        final parsed = NotificationLevel.parse(
          level,
          fallback: NotificationLevel.dmDefault,
        );
        if (parsed != NotificationLevel.dmDefault) levels[peerId] = parsed;
      }

      final envelope = row['last_message'] as Map<String, dynamic>?;
      conversations.add(
        DmConversation(
          peerId: peerId,
          peerName: handle,
          peerChatPublicKey: chatKey,
          peerSigningPublicKey: signingKey,
          // Resolved per peer by the query rather than by the client holding
          // the whole friends graph — see central migration 014.
          state: FriendshipState.parse(row['state']),
          lastMessage: envelope == null
              ? null
              : await _decryptRow(envelope, peerId: peerId, peerHandle: handle),
        ),
      );
    }
    // Signed out, or into another account, while these were read: they are
    // not the next account's to show.
    if (isClosed || _myUserId != myId) return null;

    _rememberCursors(
      latestInbound,
      unread,
      merge: before != null || peer != null,
    );
    return (
      conversations: conversations,
      unread: unread,
      levels: levels,
      hasMore: data['has_more'] == true,
      cursor: int.tryParse(
        '${(rows.lastOrNull?['last_message'] as Map?)?['id']}',
      ),
    );
  }
}
