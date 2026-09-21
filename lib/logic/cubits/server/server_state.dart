part of 'server_cubit.dart';

@JsonSerializable(explicitToJson: true)
class ServerState {
  final List<Server> servers;
  final String? selectedServerId;

  /// How recently this device chose the order [servers] is in.
  ///
  /// A Lamport counter, shared with the cloud backup — see [ServerManifest].
  /// Persisted, because the point of it is to survive a restart and still
  /// beat a stale order sitting in the cloud.
  final int orderClock;

  const ServerState({
    this.servers = const [],
    this.selectedServerId,
    this.orderClock = 0,
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

  /// What this member may do on the selected server, or null when there is no
  /// selected server — or when its profile has not loaded yet.
  ///
  /// One place for a chain that was being written out at fifteen call sites,
  /// each of them four `?.` hops deep and each free to disagree about what an
  /// absent link means. It is the same question every time: what may I do
  /// here.
  @JsonKey(includeFromJson: false, includeToJson: false)
  UserPermissions? get myPermissions => selectedServer?.user?.permissions;

  /// The same, as the bitfield `ServerPermission.has` takes.
  ///
  /// Zero when anything along the way is missing, which is the safe reading:
  /// a member whose profile has not arrived may do nothing yet.
  @JsonKey(includeFromJson: false, includeToJson: false)
  int get myPermissionBits => myPermissions?.bits ?? 0;

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
  }) {
    return ServerState(
      servers: servers ?? this.servers,
      selectedServerId: clearSelectedServerId
          ? null
          : (selectedServerId ?? this.selectedServerId),
      orderClock: orderClock ?? this.orderClock,
    );
  }

  factory ServerState.fromJson(Map<String, dynamic> json) =>
      _$ServerStateFromJson(json);

  Map<String, dynamic> toJson() => _$ServerStateToJson(this);
}
