part of 'server_cubit.dart';

@JsonSerializable(explicitToJson: true)
class ServerState {
  final List<Server> servers;
  final String? selectedServerId;

  const ServerState({this.servers = const [], this.selectedServerId});

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

  ServerState copyWith({
    List<Server>? servers,
    String? selectedServerId,
    bool clearSelectedServerId = false,
  }) {
    return ServerState(
      servers: servers ?? this.servers,
      selectedServerId: clearSelectedServerId
          ? null
          : (selectedServerId ?? this.selectedServerId),
    );
  }

  factory ServerState.fromJson(Map<String, dynamic> json) =>
      _$ServerStateFromJson(json);

  Map<String, dynamic> toJson() => _$ServerStateToJson(this);
}
