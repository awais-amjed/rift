part of 'server_notifications_cubit.dart';

/// Unread counts and notification levels across **all** joined servers.
///
/// Both halves come from one `unread_counts()` call per server, because every
/// reader of one wants the other: a badge that is drawn from one moment and a
/// mute state read at another will disagree, visibly, for as long as it takes
/// the second call to land.
///
/// Channels and server DMs are counted separately because they are badged in
/// different places — a channel tile, a conversation row — but they come from
/// the same subscription, so a server's total is simply both halves added up.
///
/// One invariant holds everywhere: **a zero count is an absent key**. Nothing
/// stores an empty inner map or a 0, so a server with no unread messages
/// simply isn't in the maps. Levels follow the same rule for the same reason:
/// a scope nobody has changed has no row on the server and no key here, and
/// [NotificationLevel.channelDefault] / [NotificationLevel.dmDefault] answer
/// for it. The `with*`/`cleared*` transforms below are the only way to change
/// any of them, which is what keeps that true.
@immutable
class NotificationsState extends Equatable {
  /// serverId → (channelId → unread count). Absent keys mean zero.
  final Map<String, Map<String, int>> unreadByServer;

  /// serverId → (peer user id → unread count) for that server's DMs.
  final Map<String, Map<String, int>> dmUnreadByServer;

  /// serverId → level for the server as a whole. An absent key is not a level
  /// but *no opinion*: what everything inside it falls back to when it has
  /// none of its own. See [NotificationLevel.resolve].
  final Map<String, NotificationLevel> serverLevels;

  /// serverId → (channelId → level). Absent keys mean the default.
  final Map<String, Map<String, NotificationLevel>> channelLevels;

  /// serverId → (peer user id → level). Absent keys mean the default.
  final Map<String, Map<String, NotificationLevel>> dmLevels;

  const NotificationsState({
    this.unreadByServer = const {},
    this.dmUnreadByServer = const {},
    this.serverLevels = const {},
    this.channelLevels = const {},
    this.dmLevels = const {},
  });

  int unreadForChannel(String serverId, String channelId) =>
      unreadByServer[serverId]?[channelId] ?? 0;

  /// Unread DMs from one peer on one server.
  int unreadForDm(String serverId, String peerId) =>
      dmUnreadByServer[serverId]?[peerId] ?? 0;

  NotificationLevel channelLevel(String serverId, String channelId) =>
      NotificationLevel.resolve(
        scope: channelLevels[serverId]?[channelId],
        server: serverLevels[serverId],
        fallback: NotificationLevel.channelDefault,
      );

  NotificationLevel dmLevel(String serverId, String peerId) =>
      NotificationLevel.resolve(
        scope: dmLevels[serverId]?[peerId],
        server: serverLevels[serverId],
        fallback: NotificationLevel.dmDefault,
      );

  /// What the server as a whole is set to, or [NotificationLevel.serverDefault]
  /// where nobody has said. Only the rail's own menu asks this — everything
  /// else wants the resolved answer above.
  NotificationLevel serverLevel(String serverId) =>
      serverLevels[serverId] ?? NotificationLevel.serverDefault;

  /// Unread DMs across all of a server's conversations — the badge on the
  /// server's "Server DMs" row.
  int dmUnreadForServer(String serverId) =>
      _sum(dmUnreadByServer, serverId, (id) => dmLevel(serverId, id));

  /// Everything unread on a server, channels and DMs together — what the rail
  /// chip and "Mark all as read" are about.
  int unreadForServer(String serverId) =>
      _sum(unreadByServer, serverId, (id) => channelLevel(serverId, id)) +
      dmUnreadForServer(serverId);

  /// Total unread across every server except [exceptServerId] (used for the
  /// "activity on another server" hint on the server header).
  int totalUnreadExcept(String? exceptServerId) {
    var total = 0;
    for (final serverId in {...unreadByServer.keys, ...dmUnreadByServer.keys}) {
      if (serverId == exceptServerId) continue;
      total += unreadForServer(serverId);
    }
    return total;
  }

  /// Replace one server's counts and levels wholesale — what a re-seed
  /// produces.
  NotificationsState withServerCounts(
    String serverId, {
    required Map<String, int> channels,
    required Map<String, int> dms,
    required Map<String, NotificationLevel> channelPrefs,
    required Map<String, NotificationLevel> dmPrefs,
    NotificationLevel? serverPref,
  }) => NotificationsState(
    unreadByServer: PerServerMap.replaced(unreadByServer, serverId, channels),
    dmUnreadByServer: PerServerMap.replaced(dmUnreadByServer, serverId, dms),
    serverLevels: _withServerLevel(serverLevels, serverId, serverPref),
    channelLevels: PerServerMap.replaced(channelLevels, serverId, channelPrefs),
    dmLevels: PerServerMap.replaced(dmLevels, serverId, dmPrefs),
  );

  /// The server as a whole. Null clears the opinion rather than storing one,
  /// which is what keeps "absent means ask the next scope out" true.
  NotificationsState withServerLevel(
    String serverId,
    NotificationLevel? level,
  ) => copyWith(serverLevels: _withServerLevel(serverLevels, serverId, level));

  /// One scope's level changed. Applied locally the moment the user picks it,
  /// so the menu closes on the answer rather than on a round trip — the write
  /// that follows either agrees or is corrected by the next re-seed.
  NotificationsState withLevel(
    String serverId,
    String scopeId,
    NotificationLevel level, {
    required bool isChannel,
  }) {
    final outer = isChannel ? channelLevels : dmLevels;
    final inner = Map<String, NotificationLevel>.from(
      outer[serverId] ?? const {},
    )..[scopeId] = level;
    final next = Map.of(outer)..[serverId] = inner;
    return isChannel ? copyWith(channelLevels: next) : copyWith(dmLevels: next);
  }

  /// One scope's opinion cleared — back to whatever the next scope out says.
  NotificationsState withoutLevel(
    String serverId,
    String scopeId, {
    required bool isChannel,
  }) {
    final next = PerServerMap.without(
      isChannel ? channelLevels : dmLevels,
      serverId,
      scopeId,
    );
    if (next == null) return this;
    return isChannel ? copyWith(channelLevels: next) : copyWith(dmLevels: next);
  }

  /// One more unread message in a channel.
  NotificationsState incremented(String serverId, String channelId) => copyWith(
    unreadByServer: PerServerMap.incremented(
      unreadByServer,
      serverId,
      channelId,
    ),
  );

  /// One more unread DM from a peer.
  NotificationsState incrementedDm(String serverId, String peerId) => copyWith(
    dmUnreadByServer: PerServerMap.incremented(
      dmUnreadByServer,
      serverId,
      peerId,
    ),
  );

  /// A channel was read. Returns `this` unchanged when it had no badge, so
  /// callers can emit unconditionally without churning identical states.
  NotificationsState clearedChannel(String serverId, String channelId) {
    final next = PerServerMap.without(unreadByServer, serverId, channelId);
    if (next == null) return this;
    return copyWith(unreadByServer: next);
  }

  /// A conversation was read. Same `this`-when-unchanged contract as
  /// [clearedChannel].
  NotificationsState clearedDm(String serverId, String peerId) {
    final next = PerServerMap.without(dmUnreadByServer, serverId, peerId);
    if (next == null) return this;
    return copyWith(dmUnreadByServer: next);
  }

  /// Drop a whole server, e.g. after leaving it.
  NotificationsState clearedServer(String serverId) {
    if (!unreadByServer.containsKey(serverId) &&
        !dmUnreadByServer.containsKey(serverId) &&
        !serverLevels.containsKey(serverId) &&
        !channelLevels.containsKey(serverId) &&
        !dmLevels.containsKey(serverId)) {
      return this;
    }
    return NotificationsState(
      unreadByServer: Map.of(unreadByServer)..remove(serverId),
      dmUnreadByServer: Map.of(dmUnreadByServer)..remove(serverId),
      serverLevels: Map.of(serverLevels)..remove(serverId),
      channelLevels: Map.of(channelLevels)..remove(serverId),
      dmLevels: Map.of(dmLevels)..remove(serverId),
    );
  }

  NotificationsState copyWith({
    Map<String, Map<String, int>>? unreadByServer,
    Map<String, Map<String, int>>? dmUnreadByServer,
    Map<String, NotificationLevel>? serverLevels,
    Map<String, Map<String, NotificationLevel>>? channelLevels,
    Map<String, Map<String, NotificationLevel>>? dmLevels,
  }) => NotificationsState(
    unreadByServer: unreadByServer ?? this.unreadByServer,
    dmUnreadByServer: dmUnreadByServer ?? this.dmUnreadByServer,
    serverLevels: serverLevels ?? this.serverLevels,
    channelLevels: channelLevels ?? this.channelLevels,
    dmLevels: dmLevels ?? this.dmLevels,
  );

  /// A server's unread total, **minus whatever is muted**.
  ///
  /// The number on the outside is a claim that something wants you, and a
  /// muted conversation has said it does not. Its own count is left alone —
  /// the channel still shows it has something in it — so this is the one place
  /// the two readings differ, which is exactly where Discord puts the
  /// difference too.
  ///
  /// [levelOf] resolves the whole chain, so muting a *server* takes its
  /// channels out of the total too, and a channel deliberately turned back up
  /// inside one still counts.
  static int _sum(
    Map<String, Map<String, int>> outer,
    String serverId,
    NotificationLevel Function(String scopeId) levelOf,
  ) {
    final inner = outer[serverId];
    if (inner == null) return 0;
    var total = 0;
    for (final entry in inner.entries) {
      if (levelOf(entry.key).isMuted) continue;
      total += entry.value;
    }
    return total;
  }

  static Map<String, NotificationLevel> _withServerLevel(
    Map<String, NotificationLevel> outer,
    String serverId,
    NotificationLevel? level,
  ) {
    final next = Map.of(outer);
    if (level == null) {
      next.remove(serverId);
    } else {
      next[serverId] = level;
    }
    return next;
  }

  @override
  List<Object?> get props => [
    unreadByServer,
    dmUnreadByServer,
    serverLevels,
    channelLevels,
    dmLevels,
  ];
}
