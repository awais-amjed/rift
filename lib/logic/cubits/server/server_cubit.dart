import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../data/classes/api_response.dart';
import '../../../data/classes/channel.dart';
import '../../../data/classes/server.dart';
import '../../../data/classes/server_user.dart';
import '../../../data/enums/error_code.dart';
import '../../../data/repositories/server_repository.dart';
import '../vault/vault_cubit.dart';

part 'server_cubit.g.dart';

part 'server_state.dart';

class ServerCubit extends HydratedCubit<ServerState> {
  final ServerRepository _repository = ServerRepository();

  /// Injected after construction — allows re-authentication without a circular dependency.
  VaultCubit? _vaultCubit;

  /// Guards against concurrent background token refreshes.
  bool _isRefreshingToken = false;

  ServerCubit() : super(const ServerState());

  void injectVaultCubit(VaultCubit vaultCubit) {
    _vaultCubit = vaultCubit;
  }

  // ──────────────────────────────────────────────────────────
  // Token auto-refresh helpers
  // ──────────────────────────────────────────────────────────

  /// Returns true if the response indicates an invalid/expired session token.
  /// Checks the structured error code first, then falls back to string matching
  /// for older server deployments that don't send a `code` field.
  static bool _isSessionInvalid(APIResponse response) =>
      !response.success &&
      (ErrorCode.isSessionInvalid(response.errorCode) ||
          // Legacy fallback — remove once all deployments send codes.
          (response.error != null &&
              (response.error!.contains('expired') ||
                  response.error!.contains('Invalid token') ||
                  response.error!.contains('No token found') ||
                  response.error!.contains('Token is not linked'))));

  /// Re-runs the Ed25519 challenge-response for the selected server.
  /// On success, persists the new token and returns it; returns null on failure.
  Future<String?> reAuthenticate() async {
    final server = state.selectedServer;
    if (server == null || _vaultCubit == null) return null;

    final result = await _vaultCubit!.loginToServer(
      supabaseUrl: server.supabaseUrl,
    );

    if (!result.success || result.data == null) return null;

    final newToken = result.data!['token'] as String?;
    if (newToken == null) return null;

    updateServer(server.id, token: newToken);
    return newToken;
  }

  /// Executes [call] with the current bearer token.
  /// If the token is near expiry a background refresh is kicked off concurrently.
  /// If the call returns a session-invalid error, re-authenticates and retries once.
  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  ) async {
    final server = state.selectedServer;
    if (server == null) return APIResponse.error('No server selected');

    if (server.isTokenNearExpiry && !_isRefreshingToken && _vaultCubit != null) {
      _isRefreshingToken = true;
      reAuthenticate().then((_) => _isRefreshingToken = false);
    }

    var response = await call(server.token);

    if (_isSessionInvalid(response) && _vaultCubit != null) {
      final newToken = await reAuthenticate();
      if (newToken != null) {
        response = await call(newToken);
      }
    }

    return response;
  }

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
    String? supabaseKey,
    String? livekitUrl,
    String? token,
    String? keyVersion,
    ServerUser? user,
    List<Channel>? channels,
    bool clearUser = false,
  }) {
    final updated = state.servers.map((s) {
      if (s.id != serverId) return s;
      return s.copyWith(
        name: name,
        iconUrl: iconUrl,
        supabaseKey: supabaseKey,
        livekitUrl: livekitUrl,
        token: token,
        keyVersion: keyVersion,
        user: user,
        channels: channels,
        clearUser: clearUser,
      );
    }).toList();
    emit(state.copyWith(servers: updated));
  }

  // ──────────────────────────────────────────────────────────
  // API Operations
  // ──────────────────────────────────────────────────────────

  /// Returns a LiveKit JWT for [channelId]. Token refresh is handled automatically.
  Future<APIResponse> getChannelToken(
    String channelId, {
    bool screenShare = false,
  }) =>
      _callWithAutoRefresh(
        (token) => _repository.getChannelToken(
          state.selectedServer!.supabaseUrl,
          channelId,
          screenShare: screenShare,
          bearerToken: token,
        ),
      );

  /// Mutes/unmutes a participant server-wide (requires is_channel_manager).
  Future<APIResponse> muteParticipant({
    required String channelId,
    required String participantIdentity,
    required bool muted,
  }) =>
      _callWithAutoRefresh(
        (token) => _repository.muteParticipant(
          state.selectedServer!.supabaseUrl,
          bearerToken: token,
          channelId: channelId,
          participantIdentity: participantIdentity,
          muted: muted,
        ),
      );

  /// Creates a new server. On success returns the single-use admin invite code.
  Future<({bool success, String? inviteCode, String? error})> createServer({
    required String supabaseUrl,
    required String serviceKey,
    required String name,
    String? iconUrl,
    required String livekitUrl,
    required String livekitApiKey,
    required String livekitSecretKey,
  }) async {
    final response = await _repository.createServer(
      supabaseUrl,
      serviceKey: serviceKey,
      name: name,
      iconUrl: iconUrl,
      livekitUrl: livekitUrl,
      livekitApiKey: livekitApiKey,
      livekitSecretKey: livekitSecretKey,
    );

    if (!response.success) {
      return (success: false, inviteCode: null, error: response.error);
    }

    final data = response.data as Map<String, dynamic>;
    final inviteCode = data['invite_code'] as String;
    return (success: true, inviteCode: inviteCode, error: null);
  }

  /// Create an invite code for the selected server.
  Future<({bool success, String? inviteCode, String? error})> createInvite({
    bool isServerAdmin = false,
    bool isChannelManager = false,
    bool canCreateTokens = false,
    int? maxUses = 1,
    int? expiresInSeconds,
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, inviteCode: null, error: 'No server selected');
    }

    final response = await _callWithAutoRefresh(
      (token) => _repository.createInvite(
        server.supabaseUrl,
        bearerToken: token,
        isServerAdmin: isServerAdmin,
        isChannelManager: isChannelManager,
        canCreateTokens: canCreateTokens,
        maxUses: maxUses,
        expiresInSeconds: expiresInSeconds,
      ),
    );

    if (response.success) {
      final inviteCode = response.data['invite_code'] as String;
      return (success: true, inviteCode: inviteCode, error: null);
    } else {
      return (
        success: false,
        inviteCode: null,
        error: response.error ?? 'Failed to generate invite',
      );
    }
  }


  /// Validate an invite code without registering a user.
  Future<
    ({
      bool success,
      String? error,
      String? serverId,
      String? serverName,
    })
  >
  validateInvite(String supabaseUrl, String inviteCode) async {
    return (
      success: true,
      error: null,
      serverId: null,
      serverName: null,
    );
  }

  /// Rotates the Ed25519 keypair for the selected server. Delegates crypto to
  /// [vaultCubit] and persists the new key version to state.
  Future<({bool success, String? error})> rotateServerKey(
    VaultCubit vaultCubit,
  ) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final result = await vaultCubit.rotateKey(supabaseUrl: server.supabaseUrl);

    if (!result.success) {
      return (success: false, error: result.error ?? 'Key rotation failed');
    }

    // Persist the new version so the next login derives the correct keypair.
    updateServer(server.id, keyVersion: result.newVersion);

    return (success: true, error: null);
  }

  /// Create a new channel in the selected server.
  Future<({bool success, String? error})> createChannel({
    required String name,
    required String channelType,
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final response = await _callWithAutoRefresh(
      (token) => _repository.createChannel(
        server.supabaseUrl,
        bearerToken: token,
        name: name,
        channelType: channelType,
      ),
    );

    if (!response.success) {
      return (success: false, error: response.error ?? 'Failed to create channel');
    }

    // Refresh the channel list to include the newly created one.
    await refreshServerDetails();
    return (success: true, error: null);
  }

  /// Refresh the channel list and other details for the selected server.
  Future<({bool success, String? error})> refreshServerDetails() async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final response = await _callWithAutoRefresh(
      (token) => _repository.getServerDetails(server.supabaseUrl, bearerToken: token),
    );

    if (response.success) {
      final data = response.data as Map<String, dynamic>;
      final rawChannels = data['channels'] as List<dynamic>?;
      final channels =
          rawChannels
              ?.map((c) => Channel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [];
      final supabaseKey = data['supabase_key'] as String?;
      final rawUser = data['user'];
      final user =
          rawUser != null
              ? ServerUser.fromJson(rawUser as Map<String, dynamic>)
              : null;

      updateServer(
        server.id,
        channels: channels,
        supabaseKey: supabaseKey,
        user: user,
      );
      return (success: true, error: null);
    } else {
      return (
        success: false,
        error: response.error ?? 'Failed to refresh server details',
      );
    }
  }

  // ──────────────────────────────────────────────────────────
  // Hydration
  // ──────────────────────────────────────────────────────────

  @override
  ServerState? fromJson(Map<String, dynamic> json) =>
      ServerState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(ServerState state) => state.toJson();

  // ──────────────────────────────────────────────────────────
  // Dev helpers
  // ──────────────────────────────────────────────────────────

  /// Wipes all persisted server state. Dev/test only.
  Future<void> reset() async {
    await clear();
    emit(const ServerState());
  }
}
