import 'dart:async';

import 'package:rift_crypto/rift_crypto.dart';

import '../../logic/helper_methods.dart';
import '../../logic/services/siws_sign_in.dart';
import '../classes/api_response.dart';
import '../classes/server.dart';
import '../classes/server_details.dart';
import '../enums/error_code.dart';
import '../member_cache.dart';
import 'attachment_repository.dart';
import 'secure_storage_repository.dart';
import 'server_repository.dart';
import 'voice_region_probe.dart';

/// A silent re-login that worked: the token it minted, and the server's own
/// account of itself that came back with it.
typedef SessionLogin = ({String serverId, String token, ServerDetails details});

/// A server's own account of itself, read again after a write that moved it.
typedef SessionDetails = ({String serverId, ServerDetails details});

/// Over the repository budget and one job: a call to one of this identity's
/// servers, from picking the server to the token, the retry and the re-read.
///
/// Being signed in to the servers this identity has joined: which server is
/// selected, each one's token, and getting a new token when one runs out.
///
/// The server list itself belongs to `ServerCubit`, which saves it; this
/// holds the copy it [publish]es on every change, so anything that only needs
/// the selection or a token can read it here instead of reaching into the
/// cubit. Signing in again needs nothing from the vault but the seed, which is
/// read from secure storage as the vault itself reads it.
///
/// A new token lands in the list by way of [logins]: the cubit hears each one
/// and writes it, with the details that came back, onto the server. The
/// stream is synchronous, so by the time [reAuthenticate] answers the list
/// already holds the token it returns.
class SessionRepository {
  final ServerRepository _servers;
  final AttachmentRepository _attachments;
  final CryptoRepository _crypto;
  final SecureStorageRepository _storage;

  SessionRepository({
    ServerRepository? servers,
    AttachmentRepository? attachments,
    CryptoRepository? crypto,
    SecureStorageRepository? storage,
  }) : _servers = servers ?? ServerRepository(),
       _attachments = attachments ?? AttachmentRepository(),
       _crypto = crypto ?? CryptoRepository(),
       _storage = storage ?? SecureStorageRepository();

  // ── The servers ───────────────────────────────────────────

  List<Server> _list = const [];
  String? _selectedId;

  /// The repository every call to a server goes through. One, shared, so
  /// each server's database client is made once rather than per feature.
  ServerRepository get repository => _servers;

  /// The same for a server's stored files, which keep their own HTTP client.
  AttachmentRepository get attachments => _attachments;

  List<Server> get servers => _list;
  String? get selectedServerId => _selectedId;
  Server? get selectedServer =>
      _selectedId == null ? null : serverById(_selectedId!);

  Server? serverById(String serverId) {
    for (final server in _list) {
      if (server.id == serverId) return server;
    }
    return null;
  }

  /// The server a call is about: [serverId] when the caller named one, the
  /// selection when it didn't. A page that can open for a server other than
  /// the current one names it, or its form writes to the wrong server.
  Server? target(String? serverId) =>
      serverId == null ? selectedServer : serverById(serverId);

  /// What to say when [target] finds nothing. A named server that isn't here
  /// is a different failure from having nothing selected, and telling them
  /// apart is the difference between "pick a server" and "this one is gone".
  String noTarget(String? serverId) => serverId == null
      ? 'No server selected'
      : 'That server is no longer on this device';

  /// Take the server list as it now stands. `ServerCubit` calls this from
  /// `onChange`, so the copy here is never a frame behind its state.
  void publish({required List<Server> servers, String? selectedServerId}) {
    _list = servers;
    _selectedId = selectedServerId;
  }

  // ── Signing in ────────────────────────────────────────────

  final _logins = StreamController<SessionLogin>.broadcast(sync: true);

  /// Every silent re-login that worked, as it lands.
  Stream<SessionLogin> get logins => _logins.stream;

  /// In-flight re-logins keyed by server id, so concurrent callers (a
  /// proactive near-expiry refresh and a reactive retry) share one SIWS
  /// login and all see its result.
  final Map<String, Future<String?>> _refreshing = {};

  /// A fresh SIWS session on the server at [supabaseUrl], signed with the key
  /// the seed derives for that (host, server) pair. Shared by re-login and by
  /// first-time registration.
  Future<({String? accessToken, String? error})> signIn(
    String supabaseUrl, {
    required String serverId,
  }) async {
    final seed = await _storage.getMasterSeed();
    if (seed == null) {
      return (accessToken: null, error: 'The vault has no master seed');
    }
    final identity = await _crypto.deriveServerIdentity(
      masterSeed: CryptoRepository.fromBase64(seed),
      host: Uri.parse(supabaseUrl).host,
      serverId: serverId,
    );
    // The host picks the *key*; it is deliberately not written into the signed
    // message, which names a fixed domain so a server can live at any address —
    // a LAN IP, a plain-http hostname — that GoTrue would otherwise reject.
    final response = await siwsSignIn(
      repository: _servers,
      crypto: _crypto,
      supabaseUrl: supabaseUrl,
      identity: identity,
    );
    if (!response.success) {
      return (accessToken: null, error: response.error);
    }
    final data = response.data as Map<String, dynamic>?;
    final accessToken = data?['access_token'] as String?;
    if (accessToken == null) {
      return (accessToken: null, error: 'Login returned no access token');
    }
    return (accessToken: accessToken, error: null);
  }

  /// Sign in to [server] again and ask it who we are there.
  ///
  /// Hands back the token and the details together, or the reason it did not
  /// work — `ServerDb.serverGone` among them, which the selection uses to
  /// notice a server deleted out from under it.
  Future<({String? token, ServerDetails? details, String? error})> login(
    Server server,
  ) async {
    try {
      final login = await signIn(server.supabaseUrl, serverId: server.id);
      final token = login.accessToken;
      if (token == null) {
        return (token: null, details: null, error: login.error);
      }

      final details = await _servers.getServerDetails(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      );
      // A login that cannot say who it logged in as has not succeeded, and
      // reporting it as one is how a deleted server became a room with no
      // channels signed in as "Guest": SIWS still works after the server is
      // gone — the GoTrue account outlives it — so the only thing that knows
      // is `get_server_details` coming back null. The transient case wants
      // the same answer for the opposite reason: the caller lands what comes
      // back, and an empty reply blanks a server that is merely unreachable.
      if (!details.success || details.data is! Map) {
        return (token: null, details: null, error: details.error);
      }
      return (
        token: token,
        details: ServerDetails.fromJson(details.data as Map<String, dynamic>),
        error: null,
      );
    } catch (e) {
      HelperMethods.printDebug('[Session] login error: $e');
      return (token: null, details: null, error: e.toString());
    }
  }

  /// Silent SIWS re-login for any joined server, not only the selected one —
  /// the notifications cubit keeps every subscribed server's token fresh so
  /// its Realtime subscription doesn't lapse. The key comes from the seed, so
  /// it never prompts. The new token is announced on [logins] and returned;
  /// null when it did not work.
  Future<String?> reAuthenticate(String serverId) {
    final existing = _refreshing[serverId];
    if (existing != null) return existing;
    final future = _reAuthenticate(serverId);
    _refreshing[serverId] = future;
    future.whenComplete(() => _refreshing.remove(serverId));
    return future;
  }

  Future<String?> _reAuthenticate(String serverId) async {
    final server = serverById(serverId);
    if (server == null) return null;

    final result = await login(server);
    final token = result.token;
    final details = result.details;
    if (token == null || details == null) return null;

    // This runs on a timer rather than on anything the user did, so it is the
    // path most likely to be the one carrying a change an operator made an
    // hour ago. The whole reply goes on, not just the token.
    _logins.add((serverId: serverId, token: token, details: details));
    return token;
  }

  // ── Calls ─────────────────────────────────────────────────

  /// Whether [response] says the session token is invalid or expired. Checks
  /// the structured error code first, then falls back to the words older
  /// servers send instead.
  static bool _isSessionInvalid(APIResponse response) =>
      !response.success &&
      (ErrorCode.isSessionInvalid(response.errorCode) ||
          // Legacy fallback — remove once all deployments send codes.
          (response.error != null &&
              (response.error!.contains('expired') ||
                  response.error!.contains('Invalid token') ||
                  response.error!.contains('No token found') ||
                  response.error!.contains('Token is not linked'))));

  /// Run [call] with [server]'s bearer token. A token near expiry starts a
  /// refresh alongside it; a call refused for its session signs in again and
  /// is tried once more.
  ///
  /// Takes the server rather than reading the selection, which is what lets
  /// a call act on a server you are not looking at.
  Future<APIResponse> callFor(
    Server server,
    Future<APIResponse> Function(String token) call,
  ) async {
    if (server.isTokenNearExpiry) {
      // Proactive; coalesced by reAuthenticate.
      unawaited(reAuthenticate(server.id));
    }

    var response = await call(server.token);

    if (_isSessionInvalid(response)) {
      final newToken = await reAuthenticate(server.id);
      if (newToken != null) response = await call(newToken);
    }
    return response;
  }

  /// [callFor] against the selected server.
  Future<APIResponse> callSelected(
    Future<APIResponse> Function(String token) call,
  ) {
    final server = selectedServer;
    if (server == null) {
      return Future.value(APIResponse.error('No server selected'));
    }
    return callFor(server, call);
  }

  /// [server]'s token for a transfer that outlasts a single call: read from
  /// the list each time it is asked, so a background refresh reaches a big
  /// upload partway through, and signed in again when asked to `refresh`.
  BearerToken bearerFor(Server server) => ({bool refresh = false}) async {
    final current = serverById(server.id) ?? server;
    if (refresh || current.isTokenNearExpiry) {
      final fresh = await reAuthenticate(server.id);
      if (fresh != null) return fresh;
    }
    return current.token;
  };

  // ── Who we have met ─────────────────────────────────────

  /// Everybody this client has met on its servers. Here because it has to
  /// outlive every page and be shared by every `MembersApi`, which holds
  /// nothing.
  final MemberCache members = MemberCache();

  // ── Where to hold a call ────────────────────────────────

  /// Which of a server's LiveKit regions this device is nearest to, and how
  /// busy each was. One for the session, so a measurement is cached across
  /// joins rather than taken again by every `VoiceApi`, which holds nothing.
  final VoiceRegionProbe regionProbe = VoiceRegionProbe();

  // ── After a write ───────────────────────────────────────

  final _details = StreamController<SessionDetails>.broadcast(sync: true);

  /// Every re-read of a server's details that [refreshDetails] made.
  /// `ServerCubit` lands each one, as it lands a re-login's.
  Stream<SessionDetails> get details => _details.stream;

  /// Read [server]'s details again and announce them on [details].
  ///
  /// For a write that moves something the server list holds — a role change
  /// moves the caller's own permission bits, a DM setting is a field on their
  /// own row. The stream is synchronous, so the list already holds the new
  /// row when this answers. A failed read announces nothing; the server's own
  /// doorbell refreshes it later, and that path is the one that notices a
  /// server deleted out from under.
  Future<bool> refreshDetails(Server server) async {
    final response = await callFor(
      server,
      (token) => _servers.getServerDetails(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      ),
    );
    if (!response.success || response.data is! Map) return false;
    _details.add((
      serverId: server.id,
      details: ServerDetails.fromJson(response.data as Map<String, dynamic>),
    ));
    return true;
  }

  Future<void> dispose() async {
    await _logins.close();
    await _details.close();
  }
}
