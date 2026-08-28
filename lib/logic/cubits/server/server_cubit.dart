import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../data/classes/api_response.dart';
import '../../../data/classes/channel.dart';
import '../../../data/classes/server.dart';
import '../../../data/classes/server_limits.dart';
import '../../../data/classes/server_member.dart';
import '../../../data/classes/server_user.dart';
import '../../../data/classes/webhook.dart';
import '../../../data/enums/error_code.dart';
import '../../../data/repositories/attachment_repository.dart';
import '../../../data/repositories/avatar_repository.dart';
import '../../../data/repositories/central_dm_repository.dart';
import '../../../data/repositories/server_repository.dart';
import '../../../supabase_config.dart';
import '../../services/avatar_cache.dart';
import '../../services/push_service.dart';
import '../../services/push_wake/wake_index.dart';
import '../vault/vault_cubit.dart';

part 'server_cubit.g.dart';

part 'server_state.dart';
part 'server_crud.dart';
part 'server_selection.dart';
part 'server_api.dart';
part 'server_members_api.dart';
part 'server_channels_api.dart';
part 'server_chat_api.dart';
part 'server_profile_api.dart';
part 'server_push_api.dart';
part 'server_webhooks_api.dart';

class ServerCubit extends HydratedCubit<ServerState>
    with
        _ServerCrudMixin,
        _ServerSelectionMixin,
        _ServerApiMixin,
        _ServerMembersApiMixin,
        _ServerChannelsApiMixin,
        _ServerChatApiMixin,
        _ServerProfileApiMixin,
        _ServerPushApiMixin,
        _ServerWebhooksApiMixin {
  @override
  final ServerRepository _repository = ServerRepository();

  /// E2E-encrypted attachment upload/download (self-hosted Storage REST).
  @override
  final AttachmentRepository _attachments = AttachmentRepository();

  /// Avatar upload/download — plaintext, unlike attachments (migration 014).
  @override
  final AvatarRepository _avatars = AvatarRepository();

  /// Central, for one thing only: minting and revoking the credential a
  /// self-hosted server forwards its pushes over. A server cannot reach a
  /// phone without one — see [_ServerPushApiMixin] — so the enrolment is part
  /// of what "turn on notifications for this server" means.
  @override
  final CentralDmRepository _central = CentralDmRepository();

  /// Keeps the snapshot the push background isolate wakes up into in step with
  /// the server list. See [_ServerPushApiMixin.refreshWakeIndex].
  @override
  final WakeIndexWriter _wakeIndex = WakeIndexWriter();

  /// Injected after construction — allows re-authentication without a circular dependency.
  @override
  VaultCubit? _vaultCubit;

  // What a direct database call needs beyond the bearer token: which project
  // to talk to, which server's rows, and which row is mine. Empty strings
  // rather than nulls so a call made with no server selected fails as a clean
  // "no rows" instead of a null assertion.
  @override
  String get _anonKey => state.selectedServer?.supabaseKey ?? '';
  @override
  String get _userId => state.selectedServer?.user?.id ?? '';

  /// The server a call is about: [serverId] when the caller named one, the
  /// selection when it didn't.
  ///
  /// Lives on the class because both API mixins resolve through it. Every method
  /// a dialog can open for a server other than the current one takes an optional
  /// `serverId` and starts here; the default keeps the call sites that genuinely
  /// mean "this server" — the chat surfaces, the sidebar — reading as they did.
  @override
  Server? _target(String? serverId) =>
      serverId == null ? state.selectedServer : state.serverById(serverId);

  /// What to say when [_target] finds nothing. A named server that isn't here is
  /// a different failure from having nothing selected, and telling them apart is
  /// the difference between "pick a server" and "this one is gone".
  @override
  String _noTarget(String? serverId) => serverId == null
      ? 'No server selected'
      : 'That server is no longer on this device';

  /// Called after the server list changes — wired to cloud auto-backup.
  @override
  void Function()? _onServersChanged;

  /// Swap one server in the list, preserving order and selection. Used by the
  /// profile API to reflect a rename/avatar change without a refetch.
  @override
  void _replaceServer(Server server) {
    emit(
      state.copyWith(
        servers: [
          for (final s in state.servers)
            if (s.id == server.id) server else s,
        ],
      ),
    );
  }

  void setOnServersChanged(void Function() callback) {
    _onServersChanged = callback;
  }

  /// Called after a structural change to a server (e.g. a channel created) —
  /// wired to the `server_events` Broadcast doorbell so other members refresh in
  /// realtime.
  ///
  /// Takes the server it happened on, because the doorbell can only ring on the
  /// topic this device is subscribed to: renaming a server you are not looking
  /// at has nobody to tell, and must not ring the bell on the one you are.
  @override
  void Function(String serverId)? _onServerEvent;

  void setOnServerEvent(void Function(String serverId) callback) {
    _onServerEvent = callback;
  }

  /// In-flight token refreshes keyed by server id, so concurrent callers
  /// (proactive near-expiry refresh + a reactive retry) coalesce onto one
  /// SIWS re-login and all observe its result.
  final Map<String, Future<String?>> _refreshing = {};

  ServerCubit() : super(const ServerState()) {
    if (PushService.isSupported) {
      PushService.instance.token.addListener(_onPushToken);
      _onPushToken();
      // Hydration is not a change, so the first snapshot has to be written
      // here or a launch that changes nothing would leave the isolate with
      // whatever an older run left behind.
      refreshWakeIndex(state);
    }
  }

  /// FCM hands the token over asynchronously and replaces it whenever it
  /// pleases, so registration is driven by the token rather than by startup —
  /// a stale one is a phone that has gone quiet without anyone noticing.
  void _onPushToken() => unawaited(registerPushDevices());

  @override
  void onChange(Change<ServerState> change) {
    super.onChange(change);
    refreshWakeIndex(change.nextState);
  }

  @override
  Future<void> close() {
    PushService.instance.token.removeListener(_onPushToken);
    return super.close();
  }

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
      anonKey: server.supabaseKey ?? '',
    );
    if (!result.success || result.data == null) return null;

    final newToken = result.data!['token'] as String?;
    if (newToken == null) return null;

    updateServer(serverId, token: newToken);
    return newToken;
  }

  /// Executes [call] with [server]'s bearer token.
  /// If the token is near expiry a background refresh is kicked off concurrently.
  /// If the call returns a session-invalid error, re-authenticates and retries once.
  ///
  /// Takes the server rather than reading the selection, which is what lets an
  /// API call act on a server you are not currently looking at. Nothing here
  /// had to change for that: [reAuthenticateServer] and its coalescing map were
  /// already keyed by server id, because the notifications cubit keeps every
  /// joined server's session fresh.
  @override
  Future<APIResponse> _callFor(
    Server server,
    Future<APIResponse> Function(String token) call,
  ) async {
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

  /// [_callFor] against the selected server — for the calls that are about
  /// whatever you are looking at (a channel token, the voice roster) rather than
  /// about a server named by the caller.
  @override
  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  ) async {
    final server = state.selectedServer;
    if (server == null) return APIResponse.error('No server selected');
    return _callFor(server, call);
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
    ServerLimits? limits,
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
        limits: limits,
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
        .map(
          (s) => {
            'id': s.id,
            'name': s.name,
            'iconUrl': s.iconUrl,
            'supabaseUrl': s.supabaseUrl,
            'supabaseKey': s.supabaseKey,
            'livekitUrl': s.livekitUrl,
            'keyVersion': s.keyVersion,
          },
        )
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
