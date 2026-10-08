part of 'server_cubit.dart';

mixin _ServerCrudMixin on Cubit<ServerState> {
  void Function()? get _onServersChanged;
  SecureStorageRepository get _storage;
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
    // Joining again is the answer to having been removed, so the note that
    // kept it out of the rail has to go with it.
    _clearServerGone(supabaseUrl: supabaseUrl, id: newServer.id);
    // And its conversations may be saved on this device again.
    MessageCacheSlot.scopesOfServer(
      supabaseUrl,
      newServer.id,
    ).forEach(MessageCache.instance.reopenScope);
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

  /// Servers this session has been told it is no longer on.
  ///
  /// Keyed the way [BackupMerge] keys a manifest entry, because the whole
  /// point is to be able to answer for one. Not persisted: it exists to stop
  /// the cloud copy resurrecting a server *between* the removal and the
  /// upload that follows it. After that upload the cloud no longer lists it,
  /// so there is nothing left to remember.
  final Set<String> _goneKeys = {};

  void noteServerGone({required String supabaseUrl, required String id}) {
    _goneKeys.add(BackupMerge.keyFor(supabaseUrl: supabaseUrl, id: id));
  }

  bool isServerGone({required String supabaseUrl, required String id}) =>
      _goneKeys.contains(BackupMerge.keyFor(supabaseUrl: supabaseUrl, id: id));

  /// Rejoining clears the note, or the merge would keep dropping a server the
  /// user has just deliberately joined again.
  void _clearServerGone({required String supabaseUrl, required String id}) {
    _goneKeys.remove(BackupMerge.keyFor(supabaseUrl: supabaseUrl, id: id));
  }

  void removeServer(String serverId) {
    // Before the server leaves the list, while there is still a session to say
    // it with: a device that stays registered on a server you have left goes
    // on being woken for it. Not awaited — leaving must not wait on a server
    // that has already stopped answering.
    unawaited(forgetPushDevice(serverId));
    _forgetSavedConversations(serverId);
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

  /// The copies of this server's channels and DMs kept on this device (see
  /// [MessageCache]). Leaving a server takes them with it: what was saved to
  /// draw a conversation faster must not outlive being able to open it.
  void _forgetSavedConversations(String serverId) {
    final server = state.servers.where((s) => s.id == serverId).firstOrNull;
    if (server == null) return;
    final scopes = MessageCacheSlot.scopesOfServer(
      server.supabaseUrl,
      server.id,
    ).toList();
    unawaited(() async {
      final seed = await _storage.getMasterSeed();
      if (seed == null) return;
      for (final scope in scopes) {
        await MessageCache.instance.forgetScope(seed, scope);
      }
    }());
  }
}
