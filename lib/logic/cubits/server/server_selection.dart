part of 'server_cubit.dart';

mixin _ServerSelectionMixin on Cubit<ServerState> {
  VaultCubit? get _vaultCubit;

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
    bool clearUser = false,
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
    );

    if (!result.success || result.data == null) return false;

    final data = result.data!;
    final token = data['token'] as String?;
    if (token == null) return false;

    final rawChannels = data['channels'] as List<dynamic>?;
    final channels = rawChannels
        ?.map((c) => Channel.fromJson(c as Map<String, dynamic>))
        .toList();
    final rawUser = data['user'];
    final user = rawUser != null
        ? ServerUser.fromJson(rawUser as Map<String, dynamic>)
        : null;

    updateServer(
      server.id,
      token: token,
      user: user,
      channels: channels,
      supabaseKey: data['supabase_key'] as String?,
    );

    return true;
  }

  /// Reconciles the in-memory server list after a vault backup import.
  /// Servers present in [importedServers] have their key version updated and
  /// token marked stale; servers not in the backup are removed.
  void syncWithImportedVault(
    List<({String url, String version})> importedServers,
  ) {
    final importedByHost = {
      for (final s in importedServers) s.url: s.version,
    };

    final updated = <Server>[];
    for (final server in state.servers) {
      final host = Uri.parse(server.supabaseUrl).host;
      final importedVersion = importedByHost[host];
      if (importedVersion != null) {
        // Stamp token as stale (epoch) so the next selectServer triggers a fresh login.
        updated.add(server.copyWith(
          keyVersion: importedVersion,
          tokenIssuedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ));
      }
      // Drop servers not in the backup.
    }

    final newSelectedId = updated.any((s) => s.id == state.selectedServerId)
        ? state.selectedServerId
        : updated.isNotEmpty
        ? updated.first.id
        : null;

    emit(state.copyWith(
      servers: updated,
      selectedServerId: newSelectedId,
      clearSelectedServerId: newSelectedId == null,
    ));

    // Re-authenticate the selected server with the restored identity.
    if (updated.isNotEmpty) loginSelectedServer();
  }

  void selectServer(Server server) {
    setSelectedServer(server);
    // Token is stale on cold start or after the near-expiry window — re-auth in the background.
    if (server.isTokenNearExpiry && _vaultCubit != null) {
      loginSelectedServer();
    }
  }
}

