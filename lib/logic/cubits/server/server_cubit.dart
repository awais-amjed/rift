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
part 'server_crud.dart';
part 'server_selection.dart';
part 'server_api.dart';

class ServerCubit extends HydratedCubit<ServerState>
    with _ServerCrudMixin, _ServerSelectionMixin, _ServerApiMixin {
  @override
  final ServerRepository _repository = ServerRepository();

  /// Injected after construction — allows re-authentication without a circular dependency.
  @override
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
  @override
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
  // Update (shared by selection, API, and token-refresh)
  // ──────────────────────────────────────────────────────────

  @override
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
  // Hydration
  // ──────────────────────────────────────────────────────────

  @override
  ServerState? fromJson(Map<String, dynamic> json) =>
      ServerState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(ServerState state) => state.toJson();

  /// Returns a serializable snapshot of the current server list for backup.
  /// Intentionally excludes [Server.token] and [Server.tokenIssuedAt].
  List<Map<String, dynamic>> getServersForExport() {
    return state.servers
        .map((s) => {
              'id': s.id,
              'name': s.name,
              'iconUrl': s.iconUrl,
              'supabaseUrl': s.supabaseUrl,
              'supabaseKey': s.supabaseKey,
              'livekitUrl': s.livekitUrl,
              'keyVersion': s.keyVersion,
            })
        .toList();
  }

  // ──────────────────────────────────────────────────────────
  // Dev helpers
  // ──────────────────────────────────────────────────────────

  /// Wipes all persisted server state. Dev/test only.
  Future<void> reset() async {
    await clear();
    emit(const ServerState());
  }
}
