part of 'server_cubit.dart';

mixin _ServerSelectionMixin on Cubit<ServerState> {
  VaultCubit? get _vaultCubit;

  Future<({bool success, String? error})> refreshServerDetails();

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
  /// [importedServers] contains full server metadata maps captured at export
  /// time. For each entry:
  ///   - If a matching server (by supabaseUrl) already exists in state, its
  ///     keyVersion is updated and token is stamped stale for re-auth.
  ///   - If no match exists (e.g. fresh device), a new [Server] is added with
  ///     a stale token so the next selection triggers a fresh login.
  /// Servers not present in the backup are removed.
  void syncWithImportedVault(List<Map<String, dynamic>> importedServers) {
    final staleTime = DateTime.fromMillisecondsSinceEpoch(0);
    final existingByUrl = {for (final s in state.servers) s.supabaseUrl: s};

    final restored = <Server>[];
    for (final meta in importedServers) {
      final url = (meta['supabaseUrl'] as String?) ?? '';
      final keyVersion = (meta['keyVersion'] as String?) ?? 'v1';

      if (url.isEmpty) continue;

      final existing = existingByUrl[url];
      if (existing != null) {
        // Existing server — update key version and mark token stale.
        restored.add(
          existing.copyWith(keyVersion: keyVersion, tokenIssuedAt: staleTime),
        );
      } else {
        // Fresh device — reconstruct a minimal Server from backup metadata.
        final id = meta['id'] as String?;
        if (id == null) continue;
        restored.add(
          Server(
            id: id,
            name: (meta['name'] as String?) ?? 'Server',
            iconUrl: meta['iconUrl'] as String?,
            supabaseUrl: url,
            supabaseKey: meta['supabaseKey'] as String?,
            livekitUrl: meta['livekitUrl'] as String?,
            token: '', // stale — login will replace it
            keyVersion: keyVersion,
            tokenIssuedAt: staleTime,
          ),
        );
      }
    }

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
      ),
    );

    // Re-authenticate the selected server with the restored identity.
    if (restored.isNotEmpty) loginSelectedServer();
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
