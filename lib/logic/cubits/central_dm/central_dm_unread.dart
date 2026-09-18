part of 'central_dm_cubit.dart';

/// Unread counts for central DMs — the badge on the rail's Home chip and on
/// each conversation row.
///
/// Derived rather than delivered — but derived *in the database*. The count is
/// one cursor per conversation in `read_state` compared against that peer's
/// messages, and `dm_conversations` (central migration 013) does the comparison
/// and hands back both the count and the cursor a read would write.
///
/// It used to be done here, over the last thousand envelopes the conversation
/// refresh had pulled, with every cursor and every notification preference
/// fetched whole beside them. All three were unbounded, and the first one was
/// unbounded *and* wrong past a thousand messages: a conversation that fell off
/// the batch lost its badge rather than showing a stale one.
///
/// Both tiers work this way now. A self-hosted server used to fan out a
/// `notifications` row per recipient per message so its client had something it
/// was allowed to subscribe to; with policies on the message tables that row
/// bought nothing, and it counts cursors too. Same table shape, same RPCs
/// (`unread_counts`, `mark_read`) — the difference between the tiers is the
/// transport, not the idea.
mixin _CentralDmUnreadMixin on Cubit<CentralDmState> {
  CentralDmRepository get _repo;
  AppCubit get _appCubit;

  /// Implemented by the conversations mixin — the only read of a notification
  /// level there is now, since the level rides on the conversation row.
  Future<void> refreshConversations();

  /// peer → newest message id known to be read.
  ///
  /// No longer fetched: it is *inferred* from the conversation list. A row with
  /// nothing unread has its cursor at or past its newest inbound message, which
  /// is all [_pushCursor] needs to know to skip a redundant write. A row with
  /// something unread is left absent, so the next read writes.
  ///
  /// The exact stored value is never needed, which is why the whole
  /// `read_state` table is no longer read — one row per conversation, fetched
  /// entire, to answer a question the same call already answers.
  final Map<String, int> _readCursors = {};

  /// peer → newest inbound id in the last refresh, which is what a read writes
  /// back. Comes from the same call as the counts, so a cursor can never skip
  /// a message that was counted a moment earlier.
  final Map<String, int> _latestInbound = {};

  /// Central DMs render on one surface only, so that's what "the user can see
  /// this" means. Without the check, a conversation left open behind the
  /// channel list would mark its own arrivals read and never badge.
  bool get _onScreen =>
      _appCubit.state.surface == HomeSurface.centralDms &&
      WindowFocusService.instance.isFocused;

  void _resetUnread() {
    _readCursors.clear();
    _latestInbound.clear();
  }

  /// How much [peerId] may interrupt. Applied locally first: the change is the
  /// user's own preference rather than a claim about the world, and the menu
  /// is closing under the pointer.
  Future<void> setNotificationLevel(
    String peerId,
    NotificationLevel level,
  ) async {
    if (isClosed) return;
    emit(
      state.copyWith(
        levelsByPeer: Map.of(state.levelsByPeer)..[peerId] = level,
      ),
    );
    final response = await _repo.setNotificationLevel(
      peerId: peerId,
      level: level,
    );
    // Put back what the server actually thinks, rather than leaving a setting
    // on screen that is in force nowhere. Through the conversation list because
    // that is where the level now comes from — its own fetch was a whole-table
    // read of `notification_prefs` to answer about the rows already on screen.
    if (!response.success) unawaited(refreshConversations());
  }

  /// Record what the conversation list said about read state.
  ///
  /// [latestInbound] is what a read writes back. [unread] is only consulted for
  /// which peers are *caught up*: those have their cursor at the newest inbound
  /// message by definition, and remembering that is what stops opening a
  /// conversation nobody has written in from posting a redundant write.
  ///
  // The call site resolves to the conversations mixin's abstract declaration,
  // which the unused-element check can't follow back here.
  // ignore: unused_element
  void _rememberCursors(
    Map<String, int> latestInbound,
    Map<String, int> unread, {
    bool merge = false,
  }) {
    // [merge] for a read of *part* of the list — one conversation, or a later
    // page. Clearing there would drop the cursors of every conversation the
    // read did not mention, and with them the "seen up to here" of each.
    if (!merge) _latestInbound.clear();
    _latestInbound.addAll(latestInbound);
    for (final entry in latestInbound.entries) {
      if (!unread.containsKey(entry.key)) _readCursors[entry.key] = entry.value;
    }
  }

  /// Takes the open conversation out of a freshly-computed [counts] when it's
  /// on screen — those messages were read as they landed. Mutates [counts]
  /// rather than emitting, so the refresh publishes one settled map instead of
  /// a count that appears and is immediately cleared.
  // ignore: unused_element
  void _readOpenConversation(Map<String, int> counts) {
    final peerId = state.openPeerId;
    if (peerId == null || !_onScreen) return;
    counts.remove(peerId);
    _pushCursor(peerId);
  }

  /// The open conversation has been seen — on opening it, on regaining focus,
  /// on arriving at the surface.
  void markOpenConversationRead() {
    final peerId = state.openPeerId;
    if (peerId == null || !_onScreen) return;
    if (!_pushCursor(peerId)) return;
    if (!state.unreadByPeer.containsKey(peerId)) return;
    emit(
      state.copyWith(unreadByPeer: Map.of(state.unreadByPeer)..remove(peerId)),
    );
  }

  /// Moves [peerId]'s cursor up to the newest inbound message and persists it.
  /// False when there was nothing newer — which is what stops a repeated focus
  /// or surface change from writing the same row over and over.
  bool _pushCursor(String peerId) {
    final latest = _latestInbound[peerId] ?? 0;
    if (latest <= (_readCursors[peerId] ?? 0)) return false;
    _readCursors[peerId] = latest;
    // Optimistic: the badge is already gone locally. A failed write self-heals
    // on the next refresh, which would simply count the messages again.
    unawaited(_repo.setReadCursor(peerId: peerId, lastReadId: latest));
    return true;
  }
}
