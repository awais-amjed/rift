import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../data/apis/push_api.dart';
import '../../../data/classes/api_response.dart';
import '../../../data/classes/channel.dart';
import '../../../data/classes/livekit_node.dart';
import '../../../data/classes/message_cache_slot.dart';
import '../../../data/classes/notice.dart';
import '../../../data/classes/server.dart';
import '../../../data/classes/server_details.dart';
import '../../../data/classes/server_limits.dart';
import '../../../data/classes/server_user.dart';
import '../../../data/classes/user_permissions.dart';
import '../../../data/repositories/secure_storage_repository.dart';
import '../../../data/repositories/server_db.dart';
import '../../../data/repositories/server_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../services/backup_merge.dart';
import '../../services/coalesced_refresh.dart';
import '../../services/hydrated_keys.dart';
import '../../services/message_cache.dart';
import '../../services/push_service.dart';
import '../../services/push_wake/wake_index.dart';
import '../../services/server_import_merge.dart';
import '../../services/server_realtime.dart';

part 'server_api.dart';
part 'server_crud.dart';
part 'server_cubit.g.dart';
part 'server_selection.dart';
part 'server_state.dart';

/// Over the cubit-hub budget and one job. The parts hold the API
/// calls; what is left here is what they all share and CODE_STYLE §5 says the
/// class must hold — the session refresh every call goes through, the
/// member-name cache, and the one place a server's row is updated.
///
/// The servers this identity has joined, and every call made to one of them.
class ServerCubit extends HydratedCubit<ServerState>
    with _ServerCrudMixin, _ServerSelectionMixin, _ServerApiMixin {
  /// The session's, so every server's database client is made once.
  @override
  late final ServerRepository _repository = _session.repository;

  /// Registering this device on the servers, as the list and the FCM token
  /// change ([PushApi]).
  @override
  late final PushApi _push = PushApi(session: _session);

  /// Keeps the snapshot the push background isolate wakes up into in step with
  /// the server list. See [_refreshWakeIndex].
  final WakeIndexWriter _wakeIndex = WakeIndexWriter();

  /// Where the seed is, for the one thing here that needs it: unsealing a
  /// server's saved conversations to forget them.
  @override
  final SecureStorageRepository _storage = SecureStorageRepository();

  /// The server a call is about: [serverId] when the caller named one, the
  /// selection when it didn't.
  ///
  /// Lives on the class because the API mixin resolves through it. Every method
  /// a dialog can open for a server other than the current one takes an optional
  /// `serverId` and starts here; the default keeps the call sites that genuinely
  /// mean "this server" — the chat surfaces, the sidebar — reading as they did.
  @override
  Server? _target(String? serverId) =>
      serverId == null ? state.selectedServer : state.serverById(serverId);

  /// What to say when [_target] finds nothing ([SessionRepository.noTarget]).
  @override
  String _noTarget(String? serverId) => _session.noTarget(serverId);

  /// Called after the server list changes — wired to cloud auto-backup.
  @override
  void Function()? _onServersChanged;

  void setOnServersChanged(void Function() callback) {
    _onServersChanged = callback;
  }

  /// Every server's one Realtime connection. Here because this cubit is what
  /// holds the servers and their tokens, and what every listener already has.
  late final ServerRealtime realtime = ServerRealtime(
    servers: stream.map((s) => s.servers),
    current: () => state.servers,
  );

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

  /// Being signed in: every call's token, and getting a new one. This cubit
  /// publishes the server list into it and writes back what a re-login
  /// learns (see [SessionRepository]).
  @override
  final SessionRepository _session;
  late final StreamSubscription<SessionLogin> _logins;
  late final StreamSubscription<SessionDetails> _rereads;

  ServerCubit({SessionRepository? session})
    : _session = session ?? SessionRepository(),
      super(const ServerState()) {
    _publishSession(state);
    _logins = _session.logins.listen(_onLogin);
    _rereads = _session.details.listen(_onDetails);
    if (PushService.isSupported) {
      PushService.instance.token.addListener(_onPushToken);
      _onPushToken();
      // Hydration is not a change, so the first snapshot has to be written
      // here or a launch that changes nothing would leave the isolate with
      // whatever an older run left behind.
      _refreshWakeIndex(state);
    }
  }

  /// A fixed name, not the class's: see [HydratedKeys].
  @override
  String get storagePrefix => HydratedKeys.server;

  /// FCM hands the token over asynchronously and replaces it whenever it
  /// pleases, so registration is driven by the token rather than by startup —
  /// a stale one is a phone that has gone quiet without anyone noticing.
  void _onPushToken() => unawaited(_push.registerPushDevices());

  /// Leave the push background isolate a snapshot of the server list.
  ///
  /// It is woken into a process that shares nothing with this one — no cubits,
  /// no hydrated storage — and cannot ask which servers this device is on. So
  /// the app writes it down. Only the fields a wake actually reads, and only
  /// when one of them has changed: the state emits on every token refresh and
  /// every selection, and neither is news to a sleeping isolate.
  ///
  /// Takes the state rather than reading it: `onChange` runs *before* the new
  /// state is installed, so the field would still hold the old list.
  void _refreshWakeIndex(ServerState current) {
    if (!PushService.isSupported) return;
    unawaited(
      _wakeIndex.update(
        WakeIndex(
          servers: [
            for (final server in current.servers)
              if (server.user != null)
                WakeServer(
                  id: server.id,
                  name: server.name,
                  supabaseUrl: server.supabaseUrl,
                  anonKey: server.supabaseKey ?? '',
                  userId: server.user!.id,
                  username: server.user!.username,
                  keyVersion: server.keyVersion,
                  channels: {
                    for (final channel in server.channels)
                      channel.id: channel.name,
                  },
                ),
          ],
        ),
      ),
    );
  }

  @override
  void onChange(Change<ServerState> change) {
    super.onChange(change);
    _publishSession(change.nextState);
    _refreshWakeIndex(change.nextState);
  }

  void _publishSession(ServerState state) => _session.publish(
    servers: state.servers,
    selectedServerId: state.selectedServerId,
  );

  /// A re-login's token and the server's reply, written onto the server.
  void _onLogin(SessionLogin login) {
    if (isClosed) return;
    applyServerDetails(login.serverId, login.details, token: login.token);
  }

  /// A feature's API re-read a server after a write that moved it.
  void _onDetails(SessionDetails read) {
    if (isClosed) return;
    applyServerDetails(read.serverId, read.details);
  }

  @override
  Future<void> close() async {
    PushService.instance.token.removeListener(_onPushToken);
    await _logins.cancel();
    await _rereads.cancel();
    await realtime.dispose();
    return super.close();
  }

  // ──────────────────────────────────────────────────────────
  // Token auto-refresh helpers
  // ──────────────────────────────────────────────────────────

  /// Silent SIWS re-login for the selected server.
  Future<String?> reAuthenticate() {
    final id = state.selectedServerId;
    if (id == null) return Future.value(null);
    return reAuthenticateServer(id);
  }

  /// Silent SIWS re-login for any joined server; see
  /// [SessionRepository.reAuthenticate].
  Future<String?> reAuthenticateServer(String serverId) =>
      _session.reAuthenticate(serverId);

  /// Executes [call] with [server]'s bearer token, signing in again and
  /// retrying once if the session has run out ([SessionRepository.callFor]).
  @override
  Future<APIResponse> _callFor(
    Server server,
    Future<APIResponse> Function(String token) call,
  ) => _session.callFor(server, call);

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
    int? storageUsed,
    int? maxFileBytes,
    List<LiveKitNode>? livekitNodes,
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
        storageUsed: storageUsed,
        maxFileBytes: maxFileBytes,
        livekitNodes: livekitNodes,
        clearUser: clearUser,
      );
    }).toList();
    emit(state.copyWith(servers: updated));
  }

  /// Land a whole `get_server_details()` reply on a server.
  ///
  /// Every path that asks the question goes through here, because the ones
  /// that picked fields out by hand each picked a different subset — and the
  /// fields nobody picked (the operator's limits, `storage_used`) were exactly
  /// the ones with no other way in. [ServerDetails] leaves anything the reply
  /// omitted as null and `copyWith` leaves a null alone, so a partial reply
  /// still cannot overwrite what we already knew.
  @override
  void applyServerDetails(
    String serverId,
    ServerDetails details, {
    String? token,
  }) {
    updateServer(
      serverId,
      token: token,
      name: details.name,
      iconUrl: details.iconUrl,
      livekitUrl: details.livekitUrl,
      supabaseKey: details.supabaseKey,
      user: details.user,
      channels: details.channels,
      limits: details.limits,
      storageUsed: details.storageUsed,
      maxFileBytes: details.maxFileBytes,
      livekitNodes: details.livekitNodes,
    );
  }

  // ──────────────────────────────────────────────────────────
  // Hydration
  // ──────────────────────────────────────────────────────────

  /// Reads the persisted list back, with any server it holds twice dropped.
  ///
  /// The healing half of the `(supabaseUrl, id)` fix: a device that imported
  /// a backup under the old URL match came out holding the same server
  /// several times, and nothing in the app can undo that — every write path
  /// maps by id and updates all the copies, and leaving removes them all
  /// together. Doing it here means such a device comes right on its next
  /// launch rather than carrying the rail entries forever.
  @override
  ServerState? fromJson(Map<String, dynamic> json) {
    final restored = ServerState.fromJson(json);
    final servers = ServerImportMerge.deduplicate(restored.servers);
    return servers.length == restored.servers.length
        ? restored
        : restored.copyWith(servers: servers);
  }

  @override
  Map<String, dynamic>? toJson(ServerState state) => state.toJson();

  /// Returns a serializable snapshot of the current server list for backup.
  /// Intentionally excludes [Server.token] and [Server.tokenIssuedAt].
  @override
  ServerManifest getServersForExport() {
    return ServerManifest(
      servers: state.servers
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
          .toList(),
      orderClock: state.orderClock,
    );
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
