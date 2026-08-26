part of 'central_dm_cubit.dart';

/// Unread counts for central DMs — the badge on the rail's Home chip and on
/// each conversation row.
///
/// Derived rather than delivered: the client already sees every message
/// addressed to it (RLS + Realtime on `dm_messages`) and the conversation
/// refresh already pulls them, so all that was ever missing is *read state* —
/// one cursor per conversation in `read_state`.
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

  /// peer → newest message id read. Absent means "never read any of it".
  final Map<String, int> _readCursors = {};

  /// peer → newest inbound id seen in the last refresh, which is what a read
  /// writes back. Refreshed by every [_countUnread].
  final Map<String, int> _latestInbound = {};

  /// Central DMs render on one surface only, so that's what "the user can see
  /// this" means. Without the check, a conversation left open behind the
  /// channel list would mark its own arrivals read and never badge.
  bool get _onScreen =>
      _appCubit.state.surface == HomeSurface.centralDms &&
      WindowFocusService.instance.isFocused;

  Future<void> _loadReadCursors() async {
    final response = await _repo.listReadCursors();
    if (isClosed || !response.success) return;
    _readCursors
      ..clear()
      ..addAll(response.data as Map<String, int>);
  }

  void _resetUnread() {
    _readCursors.clear();
    _latestInbound.clear();
  }

  /// Load how much each conversation may interrupt.
  ///
  /// Its own read rather than a field on the conversation list, because it is
  /// the caller's private opinion of the other person and has nothing to do
  /// with what the conversation contains — and because `refreshConversations`
  /// runs on every incoming message, where re-reading a setting nobody changed
  /// would be a request per message for no reason.
  Future<void> _loadNotificationLevels() async {
    final response = await _repo.listNotificationLevels();
    if (isClosed || !response.success) return;
    emit(
      state.copyWith(
        levelsByPeer: response.data as Map<String, NotificationLevel>,
      ),
    );
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
    // on screen that is in force nowhere.
    if (!response.success) unawaited(_loadNotificationLevels());
  }

  /// Per-peer unread counts for one batch of raw rows, and the cursors a read
  /// would write. Called by the conversation refresh, which has the rows.
  ///
  // The call site resolves to the conversations mixin's abstract declaration,
  // which the unused-element check can't follow back here.
  // ignore: unused_element
  Map<String, int> _countUnread(List<Map<String, dynamic>> rows, String myId) {
    final scan = DmUnreadScan.of(
      rows: rows,
      myUserId: myId,
      cursors: _readCursors,
    );
    _latestInbound
      ..clear()
      ..addAll(scan.latestInbound);
    return scan.counts;
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
