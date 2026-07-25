import 'dart:async';

import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../data/classes/api_response.dart';
import '../../../data/classes/channel.dart';
import '../../../data/classes/server.dart';
import '../../../data/classes/server_member.dart';
import '../../../data/classes/server_user.dart';
import '../../../data/enums/error_code.dart';
import '../../../data/repositories/server_repository.dart';
import '../vault/vault_cubit.dart';

part 'server_cubit.g.dart';

part 'server_state.dart';
part 'server_crud.dart';
part 'server_selection.dart';
part 'server_api.dart';
part 'server_chat_api.dart';

class ServerCubit extends HydratedCubit<ServerState>
    with _ServerCrudMixin, _ServerSelectionMixin, _ServerApiMixin, _ServerChatApiMixin {
  @override
  final ServerRepository _repository = ServerRepository();

  /// Injected after construction — allows re-authentication without a circular dependency.
  @override
  VaultCubit? _vaultCubit;

  /// Called after the server list changes — wired to cloud auto-backup.
  @override
  void Function()? _onServersChanged;

  void setOnServersChanged(void Function() callback) {
    _onServersChanged = callback;
  }

  /// Called after a structural change to the *selected* server (e.g. a channel
  /// created) — wired to the `server_events` Broadcast doorbell so other members
  /// refresh in realtime.
  @override
  void Function()? _onServerEvent;

  void setOnServerEvent(void Function() callback) {
    _onServerEvent = callback;
  }

  /// In-flight token refreshes keyed by server id, so concurrent callers
  /// (proactive near-expiry refresh + a reactive retry) coalesce onto one
  /// SIWS re-login and all observe its result.
  final Map<String, Future<String?>> _refreshing = {};

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

  /// Silent SIWS re-login for the selected server. Thin wrapper over
  /// [reAuthenticateServer].
  Future<String?> reAuthenticate() {
    final id = state.selectedServerId;
    if (id == null) return Future.value(null);
    return reAuthenticateServer(id);
  }

  /// Silent SIWS re-login for any joined server (not only the selected one — the
  /// notifications cubit keeps every subscribed server's JWT fresh so its
  /// Realtime subscription doesn't lapse). The key is derived from the seed, so
  /// it never prompts. On success persists the new JWT and returns it; null on
  /// failure. Concurrent calls for the same server share one refresh.
  Future<String?> reAuthenticateServer(String serverId) {
    final existing = _refreshing[serverId];
    if (existing != null) return existing;
    final future = _doReAuthenticate(serverId);
    _refreshing[serverId] = future;
    future.whenComplete(() => _refreshing.remove(serverId));
    return future;
  }

  Future<String?> _doReAuthenticate(String serverId) async {
    if (_vaultCubit == null) return null;
    Server? server;
    for (final s in state.servers) {
      if (s.id == serverId) {
        server = s;
        break;
      }
    }
    if (server == null) return null;

    final result = await _vaultCubit!.loginToServer(
      supabaseUrl: server.supabaseUrl,
      serverId: serverId,
    );
    if (!result.success || result.data == null) return null;

    final newToken = result.data!['token'] as String?;
    if (newToken == null) return null;

    updateServer(serverId, token: newToken);
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

    if (server.isTokenNearExpiry && _vaultCubit != null) {
      // Proactive refresh; coalesced by reAuthenticateServer.
      unawaited(reAuthenticateServer(server.id));
    }

    var response = await call(server.token);

    if (_isSessionInvalid(response) && _vaultCubit != null) {
      final newToken = await reAuthenticateServer(server.id);
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
