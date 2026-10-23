part of 'server_notifications_cubit.dart';

/// Reading and writing how much each conversation may interrupt.
///
/// The levels arrive with the unread counts — one `unread_counts()` per server
/// answers both — and go back one row at a time ([UnreadApi.setLevel]).
mixin _LevelsMixin on Cubit<NotificationsState> {
  SessionRepository get _session;
  Map<String, _ServerSub> get _subs;

  Future<void> _seed(String serverId);

  /// How much everything on [serverId] may interrupt, where it has no opinion
  /// of its own.
  ///
  /// [NotificationLevel.serverDefault] clears the row rather than storing one:
  /// a server with no opinion is what lets each channel keep its own default,
  /// and it is the same level a channel defaults to, so the menu says the same
  /// thing either way round.
  ///
  /// The other two are stored, including `all` — a server set to `all` really
  /// does turn every channel with no level of its own up to every message,
  /// which is what that row in the menu offers to do.
  Future<void> setServerLevel(String serverId, NotificationLevel level) async {
    if (isClosed) return;
    final clearing = level == NotificationLevel.serverDefault;
    emit(state.withServerLevel(serverId, clearing ? null : level));

    if (!_subs.containsKey(serverId)) return;
    final api = UnreadApi(_session.on(serverId));
    final response = clearing
        ? await api.clearLevel(scope: 'server', scopeId: serverId)
        : await api.setLevel(scope: 'server', scopeId: serverId, level: level);
    if (!response.success) unawaited(_seed(serverId));
  }

  /// How much [channelId] on [serverId] may interrupt.
  Future<void> setChannelLevel(
    String serverId,
    String channelId,
    NotificationLevel level,
  ) => _setLevel(serverId, scopeId: channelId, level: level, isChannel: true);

  /// How much the conversation with [peerId] on [serverId] may interrupt.
  Future<void> setDmLevel(
    String serverId,
    String peerId,
    NotificationLevel level,
  ) => _setLevel(serverId, scopeId: peerId, level: level, isChannel: false);

  /// Applied here first, then written.
  ///
  /// The one place in this app that shows a change before the server has
  /// agreed to it, and it earns the exception: the menu is closing under the
  /// pointer, the change is the user's own preference rather than a claim
  /// about the world, and a failed write is corrected by the next re-seed —
  /// which is at most a minute away, and immediately if anything else happens
  /// on that server.
  ///
  /// A pick here is always **stored**, even one that matches what the scope
  /// would do anyway. Picking a level for one conversation is an opinion
  /// about that conversation, and the nearest opinion wins
  /// ([NotificationLevel.resolve]). Storing nothing when it matched used to
  /// leave a channel set to "Only @mentions" following the server to "All"
  /// the next time the server was turned up. A scope nobody has picked for
  /// still has no row, so it keeps following the server and the default.
  Future<void> _setLevel(
    String serverId, {
    required String scopeId,
    required NotificationLevel level,
    required bool isChannel,
  }) async {
    if (isClosed) return;
    emit(state.withLevel(serverId, scopeId, level, isChannel: isChannel));

    if (!_subs.containsKey(serverId)) return;
    final response = await UnreadApi(_session.on(serverId)).setLevel(
      scope: isChannel ? 'channel' : 'dm',
      scopeId: scopeId,
      level: level,
    );
    // Put back whatever the server actually thinks, rather than leaving a
    // setting on screen that isn't in force anywhere.
    if (!response.success) unawaited(_seed(serverId));
  }

  /// Whether an incoming channel row names us, according to the row.
  ///
  /// The only thing here that can answer at all: the body is ciphertext and
  /// this subscription holds no channel key. `mentions` and `mentions_all` are
  /// plaintext columns the sender wrote, which is
  /// what lets a mentions-only channel be quiet for everything except the
  /// message that named you.
  ///
  /// Deliberately not used for the *wording*. A modified client could put
  /// anybody in that array, so the most it is allowed to buy is a generic
  /// "new message in #general" — the same sentence this path has always said.
  /// Claiming "mentioned you" on somebody else's say-so is a lie a chat app
  /// only has to tell once to stop being believed.
  bool _rowNamesMe(String serverId, Map<String, dynamic> row) {
    if (row['mentions_all'] == true) return true;
    final me = _subs[serverId]?.userId;
    final named = row['mentions'];
    return me != null && named is List && named.contains(me);
  }
}
