import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../../../data/classes/channel.dart';
import '../../../data/classes/server.dart';
import '../../../data/classes/server_user.dart';

part 'server_state.dart';

class ServerCubit extends HydratedCubit<ServerState> {
  ServerCubit() : super(const ServerState());

  // ──────────────────────────────────────────────────────────
  // Server selection
  // ──────────────────────────────────────────────────────────

  void setSelectedServer(Server? server) {
    emit(
      state.copyWith(
        selectedServerId: server?.id,
        clearSelectedServerId: server == null,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // CRUD
  // ──────────────────────────────────────────────────────────

  Server addServer(
    String supabaseUrl,
    String token,
    Map<String, dynamic> serverDetails,
  ) {
    final newServer = Server.fromJoin(supabaseUrl, token, serverDetails);
    final updated = [...state.servers, newServer];
    emit(state.copyWith(servers: updated, selectedServerId: newServer.id));
    return newServer;
  }

  Server addCreatedServer(
    String supabaseUrl,
    Map<String, dynamic> serverData,
    String token,
  ) {
    final newServer = Server.fromCreate(supabaseUrl, serverData, token);
    final updated = [...state.servers, newServer];
    emit(state.copyWith(servers: updated, selectedServerId: newServer.id));
    return newServer;
  }

  void removeServer(String serverId) {
    final updated = state.servers.where((s) => s.id != serverId).toList();
    String? newSelectedId = state.selectedServerId;
    if (newSelectedId == serverId) {
      newSelectedId = updated.isNotEmpty ? updated.first.id : null;
    }
    emit(
      state.copyWith(
        servers: updated,
        selectedServerId: newSelectedId,
        clearSelectedServerId: newSelectedId == null,
      ),
    );
  }

  void updateServer(
    String serverId, {
    String? name,
    String? iconUrl,
    String? livekitUrl,
    ServerUser? user,
    List<Channel>? channels,
    bool clearUser = false,
  }) {
    final updated = state.servers.map((s) {
      if (s.id != serverId) return s;
      return s.copyWith(
        name: name,
        iconUrl: iconUrl,
        livekitUrl: livekitUrl,
        user: user,
        channels: channels,
        clearUser: clearUser,
      );
    }).toList();
    emit(state.copyWith(servers: updated));
  }

  // ──────────────────────────────────────────────────────────
  // Hydration
  // ──────────────────────────────────────────────────────────

  @override
  ServerState? fromJson(Map<String, dynamic> json) =>
      ServerState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(ServerState state) => state.toJson();
}
