part of 'server_cubit.dart';

/// Every server this device has joined, in rail order, and which one is
/// selected. Persisted; the vault backup carries the same list.
@JsonSerializable(explicitToJson: true)
class ServerState extends Equatable {
  final List<Server> servers;
  final String? selectedServerId;

  /// How recently this device chose the order [servers] is in.
  ///
  /// A Lamport counter, shared with the cloud backup — see [ServerManifest].
  /// Persisted, because the point of it is to survive a restart and still
  /// beat a stale order sitting in the cloud.
  final int orderClock;

  /// The last thing to tell the person, shown once by `NoticeListeners`.
  /// Transient: a notice is news, not something to come back to.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final Notice? notice;

  const ServerState({
    this.servers = const [],
    this.selectedServerId,
    this.orderClock = 0,
    this.notice,
  });

  @JsonKey(includeFromJson: false, includeToJson: false)
  Server? get selectedServer {
    if (selectedServerId == null) {
      return servers.isNotEmpty ? servers.first : null;
    }
    return servers.cast<Server?>().firstWhere(
      (s) => s?.id == selectedServerId,
      orElse: () => servers.isNotEmpty ? servers.first : null,
    );
  }

  /// [serverId]'s server, or null with no server named — a widget drawn
  /// with nothing selected asks with its `ServerScope`'s id, which is null
  /// there. Never the selected server in its place: a page names its server
  /// (Manage server opens from the rail for any of them, the call stays on
  /// its own while another is read), and "here" means *that* server.
  Server? serverOn(String? serverId) =>
      serverId == null ? null : serverById(serverId);

  /// This member's own row on [serverId] — see [serverOn].
  ServerUser? meOn(String? serverId) => serverOn(serverId)?.user;

  /// What this member may do on [serverId], or null when it is not named —
  /// or when its profile has not loaded yet, which reads as nothing allowed.
  UserPermissions? permissionsOn(String? serverId) =>
      meOn(serverId)?.permissions;

  /// The server that lists [channelId], the selected one first — where a
  /// call is, which need not be the server on screen.
  Server? serverWithChannel(String channelId) {
    bool lists(Server server) =>
        server.channels.any((channel) => channel.id == channelId);
    final selected = selectedServer;
    if (selected != null && lists(selected)) return selected;
    for (final server in servers) {
      if (lists(server)) return server;
    }
    return null;
  }

  /// The joined server with [id], or null when this device has no such server.
  ///
  /// Deliberately without [selectedServer]'s fall back to the first server: a
  /// caller that names a server means *that* server, and quietly acting on a
  /// different one is the whole bug this lookup exists to prevent.
  Server? serverById(String id) {
    for (final server in servers) {
      if (server.id == id) return server;
    }
    return null;
  }

  ServerState copyWith({
    List<Server>? servers,
    String? selectedServerId,
    bool clearSelectedServerId = false,
    int? orderClock,
    Notice? notice,
  }) {
    return ServerState(
      servers: servers ?? this.servers,
      selectedServerId: clearSelectedServerId
          ? null
          : (selectedServerId ?? this.selectedServerId),
      orderClock: orderClock ?? this.orderClock,
      notice: notice ?? this.notice,
    );
  }

  factory ServerState.fromJson(Map<String, dynamic> json) =>
      _$ServerStateFromJson(json);

  Map<String, dynamic> toJson() => _$ServerStateToJson(this);

  @override
  List<Object?> get props => [servers, selectedServerId, orderClock, notice];
}
