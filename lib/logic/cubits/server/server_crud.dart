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

  /// Move the server at [from] so that it ends up at [to].
  ///
  /// Both are indices into the final list, which is what `onReorderItem`
  /// hands over — the older `onReorder` gave an insertion point into the
  /// unshortened one and left the off-by-one to the caller.
  ///
  /// The clock is a plain +1 rather than a timestamp: this device's clock is
  /// already the highest it has seen, because every merge adopts the higher
  /// of the two. So the order chosen *after* learning of another device's
  /// order outranks it, and two clocks that never met are decided by
  /// whichever device uploads second — see [BackupMerge].
  void reorderServers(int from, int to) {
    final count = state.servers.length;
    if (from < 0 || from >= count || to < 0 || to >= count || from == to) {
      return;
    }

    final updated = [...state.servers];
    updated.insert(to, updated.removeAt(from));
    emit(state.copyWith(servers: updated, orderClock: state.orderClock + 1));
    _onServersChanged?.call();
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
