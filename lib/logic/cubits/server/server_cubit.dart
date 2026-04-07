import 'package:flutter/foundation.dart';
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

  /// Injected by [injectVaultCubit] after construction.
  VaultCubit? _vaultCubit;

  /// Guards against concurrent background token refreshes.
  bool _isRefreshingToken = false;

  ServerCubit() : super(const ServerState());

  /// Wire up the VaultCubit so this cubit can re-authenticate on token expiry.
  void injectVaultCubit(VaultCubit vaultCubit) {
    _vaultCubit = vaultCubit;
  }

  // ──────────────────────────────────────────────────────────
  // Token auto-refresh helpers
  // ──────────────────────────────────────────────────────────

  /// Returns true when an API response indicates the session token is no
  /// longer valid and the client should attempt re-authentication.
  ///
  /// Checks the structured [errorCode] first; falls back to the human-readable
  /// [error] string for responses from older server deployments that don't yet
  /// include the `code` field.
  static bool _isSessionInvalid(APIResponse response) =>
      !response.success &&
      (ErrorCode.isSessionInvalid(response.errorCode) ||
          // Legacy fallback — remove once all deployments send codes.
          (response.error != null &&
              (response.error!.contains('expired') ||
                  response.error!.contains('Invalid token') ||
                  response.error!.contains('No token found') ||
                  response.error!.contains('Token is not linked'))));

  /// Re-run the Ed25519 challenge-response for the selected server.
  ///
  /// On success, writes the fresh token into persisted state and returns it.
  /// Returns null if re-auth fails or VaultCubit is not available.
  Future<String?> reAuthenticate() async {
    final server = state.selectedServer;
    if (server == null) {
      debugPrint('[ServerCubit] reAuthenticate: no selected server');
      return null;
    }
    if (_vaultCubit == null) {
      debugPrint('[ServerCubit] reAuthenticate: VaultCubit not injected');
      return null;
    }

    debugPrint('[ServerCubit] reAuthenticate: calling loginToServer for ${server.supabaseUrl}');
    final result = await _vaultCubit!.loginToServer(
      supabaseUrl: server.supabaseUrl,
    );

    debugPrint('[ServerCubit] reAuthenticate: loginToServer => success=${result.success}, error="${result.error}"');

    if (!result.success || result.data == null) {
      debugPrint('[ServerCubit] reAuthenticate: FAILED — ${result.error}');
      return null;
    }

    final newToken = result.data!['token'] as String?;
    if (newToken == null) {
      debugPrint('[ServerCubit] reAuthenticate: FAILED — response had no "token" field. Keys: ${result.data!.keys.toList()}');
      return null;
    }

    debugPrint('[ServerCubit] reAuthenticate: SUCCESS — new token obtained, updating server state');
    updateServer(server.id, token: newToken);
    return newToken;
  }

  /// Run [call] with the current token.
  /// If the server returns a token-expired error and [_vaultCubit] is
  /// available, re-authenticates once and retries automatically.
  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  ) async {
    final server = state.selectedServer;
    if (server == null) return APIResponse.error('No server selected');

    // Proactive background refresh: if the token has < 10 minutes left, kick
    // off a silent re-auth concurrently. The current call proceeds with the
    // still-valid existing token; all subsequent calls will use the new one.
    if (server.isTokenNearExpiry && !_isRefreshingToken && _vaultCubit != null) {
      _isRefreshingToken = true;
      reAuthenticate().then((_) => _isRefreshingToken = false);
    }

    var response = await call(server.token);

    // Reactive fallback: token expired before the background refresh completed
    // (e.g. app resumed after a long pause). Re-auth and retry once.
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

  /// Create a new server. On success returns the single-use admin invite code
  /// that the caller should use to register the first (admin) user account.
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
        token,
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


  /// Validate an invite code — looks up the invite on the server,
  /// does NOT create a user yet.
  Future<
    ({
      bool success,
      String? error,
      String? serverId,
      String? serverName,
    })
  >
  validateInvite(String supabaseUrl, String inviteCode) async {
    // For now, we can't validate without registering.
    // The client will call register directly with the invite code.
    // This is a placeholder for future invite preview functionality.
    return (
      success: true,
      error: null,
      serverId: null,
      serverName: null,
    );
  }

  /// Rotate the Ed25519 keypair for the currently selected server and
  /// persist the new key version in both SecureStorage and HydratedBloc state.
  ///
  /// Delegates all cryptographic work to [vaultCubit], then writes the bumped
  /// version back so the next cold-start login derives the correct keypair.
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

    // Write the new version back into persisted state so the next login
    // derives the correct (rotated) keypair.
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
        token,
        name: name,
        channelType: channelType,
      ),
    );

    if (!response.success) {
      return (success: false, error: response.error ?? 'Failed to create channel');
    }

    // Refresh channels to pick up the newly created one.
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
      (token) => _repository.getServerDetails(server.supabaseUrl, token),
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

  /// Wipe all persisted server state and reset to empty.
  ///
  /// Only intended for use during development / testing.
  Future<void> reset() async {
    await clear(); // removes HydratedBloc storage for this cubit
    emit(const ServerState());
  }
}
