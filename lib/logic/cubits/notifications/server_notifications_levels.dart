part of 'server_notifications_cubit.dart';

/// Reading and writing how much each conversation may interrupt.
///
/// The levels arrive with the unread counts — one `unread_counts()` per server
/// answers both — and go back one row at a time, straight to
/// `notification_prefs` under its own-row policy. There is no RPC because
/// there is no rule an RPC would enforce that the policy doesn't: a member may
/// set their own, and nobody else's.
mixin _LevelsMixin on Cubit<NotificationsState> {
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

    final sub = _subs[serverId];
    if (sub == null) return;
    try {
      if (clearing) {
        await _deleteLevel(sub, scope: 'server', scopeId: serverId);
      } else {
        await _upsertLevel(
          sub,
          scope: 'server',
          scopeId: serverId,
          level: level,
        );
      }
    } catch (_) {
      unawaited(_seed(serverId));
    }
  }

  /// How much [channelId] on [serverId] may interrupt.
  Future<void> setChannelLevel(
    String serverId,
    String channelId,
    NotificationLevel level,
  ) => _setLevel(
    serverId,
    scopeId: channelId,
    level: level,
    isChannel: true,
    fallback: NotificationLevel.channelDefault,
  );

  /// How much the conversation with [peerId] on [serverId] may interrupt.
  Future<void> setDmLevel(
    String serverId,
    String peerId,
    NotificationLevel level,
  ) => _setLevel(
    serverId,
    scopeId: peerId,
    level: level,
    isChannel: false,
    fallback: NotificationLevel.dmDefault,
  );

  /// Applied here first, then written.
  ///
  /// The one place in this app that shows a change before the server has
  /// agreed to it, and it earns the exception: the menu is closing under the
  /// pointer, the change is the user's own preference rather than a claim
  /// about the world, and a failed write is corrected by the next re-seed —
  /// which is at most a minute away, and immediately if anything else happens
  /// on that server.
  ///
  /// Choosing the default **deletes** the row rather than storing it. A scope
  /// nobody has an opinion about should have no row, so that changing what the
  /// default means later changes it for everyone who never said otherwise.
  Future<void> _setLevel(
    String serverId, {
    required String scopeId,
    required NotificationLevel level,
    required bool isChannel,
    required NotificationLevel fallback,
  }) async {
    if (isClosed) return;
    // "Same as the default" is stored as nothing at all — but the default here
    // is what the *server* says where it has an opinion, so the row has to go
    // for that fallback to be reachable again.
    final clearing = level == _effectiveDefault(serverId, fallback);
    emit(
      clearing
          ? state.withoutLevel(serverId, scopeId, isChannel: isChannel)
          : state.withLevel(serverId, scopeId, level, isChannel: isChannel),
    );

    final sub = _subs[serverId];
    if (sub == null) return;
    final scope = isChannel ? 'channel' : 'dm';
    try {
      if (clearing) {
        await _deleteLevel(sub, scope: scope, scopeId: scopeId);
      } else {
        await _upsertLevel(sub, scope: scope, scopeId: scopeId, level: level);
      }
    } catch (_) {
      // Put back whatever the server actually thinks, rather than leaving a
      // setting on screen that isn't in force anywhere.
      unawaited(_seed(serverId));
    }
  }

  /// What this scope would fall back to with no row of its own: the server's
  /// level where it has one, the scope's own default where it doesn't.
  NotificationLevel _effectiveDefault(
    String serverId,
    NotificationLevel fallback,
  ) => NotificationLevel.resolve(
    server: state.serverLevels[serverId],
    fallback: fallback,
  );

  Future<void> _upsertLevel(
    _ServerSub sub, {
    required String scope,
    required String scopeId,
    required NotificationLevel level,
  }) => sub.client.from('notification_prefs').upsert({
    'user_id': sub.userId,
    'scope': scope,
    'scope_id': scopeId,
    'level': level.toJson(),
  }, onConflict: 'user_id,scope,scope_id');

  Future<void> _deleteLevel(
    _ServerSub sub, {
    required String scope,
    required String scopeId,
  }) => sub.client
      .from('notification_prefs')
      .delete()
      .eq('user_id', sub.userId)
      .eq('scope', scope)
      .eq('scope_id', scopeId);

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
