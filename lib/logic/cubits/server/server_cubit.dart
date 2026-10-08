import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:equatable/equatable.dart';
import 'package:http/http.dart' as http;
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../data/classes/api_response.dart';
import '../../../data/classes/attachment.dart';
import '../../../data/classes/channel.dart';
import '../../../data/classes/livekit_node.dart';
import '../../../data/classes/member_page.dart';
import '../../../data/classes/message_cache_slot.dart';
import '../../../data/classes/notice.dart';
import '../../../data/classes/pending_attachment.dart';
import '../../../data/classes/region_load.dart';
import '../../../data/classes/resolved_invite.dart';
import '../../../data/classes/server.dart';
import '../../../data/classes/server_details.dart';
import '../../../data/classes/server_limits.dart';
import '../../../data/classes/server_member.dart';
import '../../../data/classes/server_user.dart';
import '../../../data/classes/user_permissions.dart';
import '../../../data/invite_link.dart';
import '../../../data/repositories/attachment_repository.dart';
import '../../../data/repositories/avatar_repository.dart';
import '../../../data/repositories/blob/blob_sink.dart';
import '../../../data/repositories/central_dm_repository.dart';
import '../../../data/repositories/secure_storage_repository.dart';
import '../../../data/repositories/server_db.dart';
import '../../../data/repositories/server_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../data/repositories/voice_region_probe.dart';
import '../../../supabase_config.dart';
import '../../services/backup_merge.dart';
import '../../services/coalesced_refresh.dart';
import '../../services/hydrated_keys.dart';
import '../../services/media_store.dart';
import '../../services/message_cache.dart';
import '../../services/push_service.dart';
import '../../services/push_wake/wake_index.dart';
import '../../services/server_import_merge.dart';
import '../../services/server_realtime.dart';

part 'server_api.dart';
part 'server_attachments_api.dart';
part 'server_bots_api.dart';
part 'server_channels_api.dart';
part 'server_chat_api.dart';
part 'server_crud.dart';
part 'server_cubit.g.dart';
part 'server_dm_calls_api.dart';
part 'server_dms_api.dart';
part 'server_invites_api.dart';
part 'server_member_lookup_api.dart';
part 'server_members_api.dart';
part 'server_ownership_api.dart';
part 'server_pins_polls_api.dart';
part 'server_private_channels_api.dart';
part 'server_profile_api.dart';
part 'server_push_api.dart';
part 'server_selection.dart';
part 'server_state.dart';
part 'server_voice_api.dart';
part 'server_voice_regions_api.dart';

/// Over the cubit-hub budget and one job. The parts hold the API
/// calls; what is left here is what they all share and CODE_STYLE §5 says the
/// class must hold — the session refresh every call goes through, the
/// member-name cache, and the one place a server's row is updated.
///
/// The servers this identity has joined, and every call made to one of them.
class ServerCubit extends HydratedCubit<ServerState>
    with
        _ServerCrudMixin,
        _ServerSelectionMixin,
        _ServerApiMixin,
        _ServerMemberLookupApiMixin,
        _ServerMembersApiMixin,
        _ServerOwnershipApiMixin,
        _ServerBotsApiMixin,
        _ServerChannelsApiMixin,
        _ServerPrivateChannelsApiMixin,
        _ServerChatApiMixin,
        _ServerAttachmentsApiMixin,
        _ServerDmCallsApiMixin,
        _ServerDmsApiMixin,
        _ServerPinsPollsApiMixin,
        _ServerVoiceApiMixin,
        _ServerVoiceRegionsApiMixin,
        _ServerInvitesApiMixin,
        _ServerProfileApiMixin,
        _ServerPushApiMixin {
  /// The session's, so every server's database client is made once.
  @override
  late final ServerRepository _repository = _session.repository;

  /// Which of a server's LiveKit nodes this device is nearest to. Held here
  /// rather than made per call so the measurement is cached across joins.
  @override
  final VoiceRegionProbe _regionProbe = VoiceRegionProbe();

  /// E2E-encrypted attachment upload/download (self-hosted Storage REST).
  @override
  final AttachmentRepository _attachments = AttachmentRepository();

  /// Avatar upload/download — plaintext, unlike attachments.
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

  /// Everybody this client has met, `serverId → userId → member`.
  ///
  /// Here rather than in a mixin because both member mixins use it and the
  /// class is where shared internals meet (CODE_STYLE §5). Its job changed when
  /// the roster stopped arriving whole: it used to save a round trip on top of
  /// a list we already held, and it is now the only in-memory record of
  /// somebody we have seen at all.
  ///
  /// Keyed by server because a user id only means something on the server it
  /// came from — and because listing another server's members would otherwise
  /// evict the entries the chat surfaces are about to ask for.
  @override
  final Map<String, Map<String, ServerMember>> _memberCache = {};

  /// Remember [members] against [serverId], and hand them back unchanged so a
  /// caller can wrap a fetch in it.
  @override
  List<ServerMember> _remember(String serverId, List<ServerMember> members) {
    final cache = _memberCache.putIfAbsent(serverId, () => {});
    for (final member in members) {
      cache[member.id] = member;
    }
    return members;
  }

  /// Where the seed is, for the one thing here that needs it: unsealing a
  /// server's saved conversations to forget them.
  @override
  final SecureStorageRepository _storage = SecureStorageRepository();

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

  /// The server a call is aimed at, and the refresher that goes with it.
  ///
  /// Every chat call used to read `state.selectedServer`, which is right for
  /// the conversation somebody is looking at and wrong for the one they are
  /// forwarding into — a forward's destination is named by the caller and is
  /// routinely on another server entirely. Resolving both together is what
  /// stops the two halves disagreeing: sealing for one server and posting the
  /// envelope to another produces a message nobody in either room can open.
  @override
  ({Server server, String anonKey})? _chatTarget(String? serverId) {
    final server = _target(serverId);
    final anonKey = server?.supabaseKey;
    if (server == null || anonKey == null) return null;
    return (server: server, anonKey: anonKey);
  }

  /// What to say when [_target] finds nothing ([SessionRepository.noTarget]).
  @override
  String _noTarget(String? serverId) => _session.noTarget(serverId);

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
      refreshWakeIndex(state);
    }
  }

  /// A fixed name, not the class's: see [HydratedKeys].
  @override
  String get storagePrefix => HydratedKeys.server;

  /// FCM hands the token over asynchronously and replaces it whenever it
  /// pleases, so registration is driven by the token rather than by startup —
  /// a stale one is a phone that has gone quiet without anyone noticing.
  void _onPushToken() => unawaited(registerPushDevices());

  @override
  void onChange(Change<ServerState> change) {
    super.onChange(change);
    _publishSession(change.nextState);
    refreshWakeIndex(change.nextState);
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

  /// [server]'s token for a transfer that outlasts a single call.
  @override
  BearerToken _bearerFor(Server server) => _session.bearerFor(server);

  /// [_callFor] against the selected server — for the calls that are about
  /// whatever you are looking at (a channel token, the voice roster) rather than
  /// about a server named by the caller.
  @override
  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  ) => _session.callSelected(call);

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
