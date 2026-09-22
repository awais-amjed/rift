part of 'server_cubit.dart';

mixin _ServerSelectionMixin on Cubit<ServerState> {
  VaultCubit? get _vaultCubit;

  Future<({bool success, String? error})> refreshServerDetails();

  /// Implemented by [ServerCubit].
  ServerManifest getServersForExport();

  void updateServer(
    String serverId, {
    String? name,
    String? iconUrl,
    String? supabaseKey,
    String? livekitUrl,
    String? token,
    String? keyVersion,
    ServerUser? user,
    List<Channel>? channels,
    ServerLimits? limits,
    int? storageUsed,
    bool clearUser = false,
  });

  /// Implemented by [ServerCubit]: land a whole `get_server_details()` reply.
  void applyServerDetails(
    String serverId,
    ServerDetails details, {
    String? token,
  });

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

  /// Performs a challenge-response login for the selected server and updates
  /// its token, user, and channel list. Returns true on success.
  Future<bool> loginSelectedServer() async {
    final server = state.selectedServer;
    if (server == null || _vaultCubit == null) return false;

    final result = await _vaultCubit!.loginToServer(
      supabaseUrl: server.supabaseUrl,
      serverId: server.id,
      anonKey: server.supabaseKey ?? '',
    );

    if (!result.success || result.data == null) return false;

    final data = result.data!;
    final token = data['token'] as String?;
    if (token == null) return false;

    // The whole reply, not the four fields this used to pick out: a cold start
    // is the only time most clients ask, so dropping the rest here meant a
    // renamed server, a moved LiveKit URL and every operator limit waited for
    // a refresh that might never come.
    applyServerDetails(server.id, ServerDetails.fromJson(data), token: token);

    return true;
  }

  /// Reconciles the in-memory server list after a vault backup import.
  ///
  /// The matching rule lives in [ServerImportMerge], which is where the
  /// reasoning about `(supabaseUrl, id)` is written down — this used to match
  /// on the URL alone and collapse every server on a project into one.
  ///
  /// Whatever comes back is stamped stale, so the next selection logs in with
  /// the restored identity rather than a token minted for the old one.
  /// Servers the backup does not mention are removed.
  void syncWithImportedVault(ServerManifest imported) {
    final restored = ServerImportMerge.apply(
      existing: state.servers,
      imported: imported.servers,
    );

    final newSelectedId = restored.any((s) => s.id == state.selectedServerId)
        ? state.selectedServerId
        : restored.isNotEmpty
        ? restored.first.id
        : null;

    emit(
      state.copyWith(
        servers: restored,
        selectedServerId: newSelectedId,
        clearSelectedServerId: newSelectedId == null,
        // Adopted, not reset: the restored order came from somewhere, and a
        // device that forgot how recent it was would lose the next tie to a
        // stale copy it had just been handed.
        orderClock: imported.orderClock,
      ),
    );

    // Re-authenticate the selected server with the restored identity.
    if (restored.isNotEmpty) loginSelectedServer();
  }

  /// Combines the cloud's server list with this device's and lands it.
  ///
  /// Two different questions come back, and conflating them is how an
  /// offline reorder gets stranded: `railChanged` is whether *this device*
  /// has something new to draw, and `cloudStale` is whether the *cloud* is
  /// missing something this device holds. A device that reordered with no
  /// network answers false and true — nothing to redraw, everything left to
  /// say.
  ({bool railChanged, bool cloudStale}) mergeCloudManifest(
    ServerManifest theirs,
  ) {
    final merged = BackupMerge.union(
      mine: getServersForExport(),
      theirs: theirs,
    );
    return (
      railChanged: applyMergedVault(merged),
      cloudStale: !merged.agreesOnOrderWith(theirs),
    );
  }

  /// Lands the result of a [BackupMerge] — the cloud's list combined with
  /// this one — without treating it as a restore.
  ///
  /// The difference from [syncWithImportedVault] is what happens to the
  /// servers this device already holds: here they keep their objects, and so
  /// their live tokens and loaded channels. A merge runs on every upload and
  /// every time the window is focused, and stamping every token stale that
  /// often would re-authenticate the whole rail for nothing.
  ///
  /// Returns true when anything actually moved, so a caller can skip the
  /// upload that would otherwise follow a merge that changed nothing.
  bool applyMergedVault(ServerManifest merged) {
    final ordered = <Server>[];
    var arrived = false;

    for (final meta in merged.servers) {
      final url = (meta['supabaseUrl'] as String?) ?? '';
      final id = meta['id'] as String?;
      if (url.isEmpty || id == null) continue;

      final known = state.serverById(id);
      if (known != null && known.supabaseUrl == url) {
        ordered.add(known);
        continue;
      }
      // Joined on another device. A stub is enough to draw the rail and to
      // log in; `get_server_details` fills the rest on first selection.
      arrived = true;
      // The vault blob is a separate record of which projects this identity
      // has joined, and it is all a v1 restore has to go on — so a host
      // learnt from the cloud has to be written there too, or the two halves
      // of the same backup disagree.
      unawaited(
        _vaultCubit?.noteJoinedHost(
              url,
              version: (meta['keyVersion'] as String?) ?? 'v1',
            ) ??
            Future<void>.value(),
      );
      ordered.add(
        Server(
          id: id,
          name: (meta['name'] as String?) ?? 'Server',
          iconUrl: meta['iconUrl'] as String?,
          supabaseUrl: url,
          supabaseKey: meta['supabaseKey'] as String?,
          livekitUrl: meta['livekitUrl'] as String?,
          token: '',
          keyVersion: (meta['keyVersion'] as String?) ?? 'v1',
          tokenIssuedAt: ServerImportMerge.stale,
        ),
      );
    }

    // A merge is a union, so every local server should already be in
    // `merged`. Should is not the same as is, and the cost of being wrong
    // here is a server vanishing from the rail — so anything unaccounted for
    // is kept, at the end.
    final placed = {for (final s in ordered) s.id};
    for (final server in state.servers) {
      if (placed.add(server.id)) ordered.add(server);
    }

    final sameOrder =
        ordered.length == state.servers.length &&
        !arrived &&
        [for (final s in ordered) s.id].join() ==
            [for (final s in state.servers) s.id].join();
    if (sameOrder && merged.orderClock == state.orderClock) return false;

    emit(state.copyWith(servers: ordered, orderClock: merged.orderClock));
    return !sameOrder;
  }

  void selectServer(Server server) {
    setSelectedServer(server);
    if (_vaultCubit == null) return;
    // Always pull fresh details on select so channels/permissions changed while
    // this server was in the background appear immediately. A stale token
    // (cold start / past the near-expiry window) re-auths first; otherwise a
    // lightweight details refresh on the current token.
    if (server.isTokenNearExpiry) {
      loginSelectedServer();
    } else {
      refreshServerDetails();
    }
  }
}
