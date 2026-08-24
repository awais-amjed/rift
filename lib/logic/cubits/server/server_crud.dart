part of 'server_cubit.dart';

mixin _ServerCrudMixin on Cubit<ServerState> {
  void Function()? get _onServersChanged;
  Future<void> forgetPushDevice(String serverId);
  Future<void> registerPushDevices();

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
    _onServersChanged?.call();
    // The FCM token listener only fires when the token changes, and joining is
    // not that — so a server joined mid-session would otherwise go unregistered
    // until the next launch.
    unawaited(registerPushDevices());
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
    _onServersChanged?.call();
    unawaited(registerPushDevices());
    return newServer;
  }

  void removeServer(String serverId) {
    // Before the server leaves the list, while there is still a session to say
    // it with: a device that stays registered on a server you have left goes
    // on being woken for it. Not awaited — leaving must not wait on a server
    // that has already stopped answering.
    unawaited(forgetPushDevice(serverId));
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
    _onServersChanged?.call();
  }
}
