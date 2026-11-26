import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart' hide ErrorCode;

import '../classes/api_response.dart';
import '../enums/error_code.dart';

/// Authenticated PostgREST access to a self-hosted server's database.
///
/// Most of what the client does is now an ordinary table call under the
/// row-level security policies rather than an edge function. That is only
/// safe because those policies exist: before them the anon key — which every
/// member holds — could read and delete every message on a server, so "clients
/// never touch tables" was a convention, not a boundary.
///
/// One client per (url, key) is cached: a `SupabaseClient` is cheap but not
/// free, and a server is talked to over and over. Several servers can share
/// one project, and so one client, each signed in with its own token — and
/// the token rotates underneath us besides, since a silent SIWS re-login hands
/// back a new JWT. So no call holds the client itself: it holds a
/// [ServerDbClient], which puts its own token on each query as the query is
/// built.
class ServerDb {
  /// What a details read answers when the server has no row for us: it was
  /// deleted, or we were removed. Named, because the cubit acts on exactly
  /// this string and nothing else.
  static const String serverGone = 'Server not found';

  final Map<String, SupabaseClient> _clients = {};

  /// For a test; the app's clients make their own connections.
  final http.Client? _http;

  ServerDb({http.Client? httpClient}) : _http = httpClient;

  ServerDbClient client(String url, String anonKey, String? bearerToken) =>
      ServerDbClient._(
        _clients.putIfAbsent(
          '$url|$anonKey',
          () => SupabaseClient(url, anonKey, httpClient: _http),
        ),
        {
          'apikey': anonKey,
          if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
        },
      );

  /// A bare `snake_case` token, which is how the migrations spell a raised
  /// error — as opposed to the sentences Postgres itself raises.
  static final RegExp _raisedCode = RegExp(r'^[a-z][a-z0-9_]{2,40}$');

  /// The statuses the gateway in front of PostgREST answers with for itself,
  /// carried as the error's code since its body has none of PostgREST's own.
  /// A 500 is left out: that one is the database's. As `CentralFailure`.
  static const Set<String> _gateway = {'502', '503', '504'};

  /// Send with [paths] named, or, to a server from before console 1.9.0,
  /// without.
  ///
  /// [send] is given the paths to put in `attachment_paths`, or null to leave
  /// the column out: always for a message with no files, so one is sent
  /// exactly as before, and on the second try when the server answered
  /// PostgREST's `PGRST204`, which is a column it does not have. That server
  /// keeps the files until its sweep's watermark passes them, as it always
  /// did; the message itself is the same either way.
  static Future<APIResponse> withFilesNamed(
    List<String> paths,
    Future<APIResponse> Function(List<String>? paths) send,
  ) async {
    if (paths.isEmpty) return send(null);
    final sent = await send(paths);
    if (sent.errorCode != 'PGRST204') return sent;
    return send(null);
  }

  /// Runs one database call and turns whatever comes back — rows, an RPC's
  /// json, an exception — into the [APIResponse] the rest of the app speaks.
  ///
  /// The error mapping matters more than it looks: `ServerCubit` decides
  /// whether to attempt a silent re-login by looking at [APIResponse.errorCode],
  /// so a PostgREST "JWT expired" has to arrive as [ErrorCode.tokenExpired] or
  /// sessions would simply stop working after an hour instead of refreshing.
  static Future<APIResponse> run(Future<dynamic> Function() body) async {
    try {
      return APIResponse.success(await body());
    } on PostgrestException catch (e) {
      final message = e.message;
      // The gateway answering for PostgREST: down, restarting, or too slow.
      // That is no answer from the database, not a no, so it is retried like
      // a dead socket. Read as a refusal, a send whose insert stored after the
      // gateway gave up on it was given back and its files deleted, leaving
      // a stored message naming files that were gone (live check, Nov 22).
      if (_gateway.contains(e.code)) {
        return e.code == '504'
            ? APIResponse.error(
                "This server isn't responding — it may be offline. Try again later.",
                errorCode: ErrorCode.serverTimeout,
              )
            : APIResponse.error(
                "Can't reach this server. It may be offline, or check your connection.",
                errorCode: ErrorCode.serverUnreachable,
              );
      }
      if (e.code == 'PGRST301' ||
          message.contains('JWT') ||
          message.contains('expired')) {
        return APIResponse(
          success: false,
          error: message,
          errorCode: ErrorCode.tokenExpired,
        );
      }
      // A RAISE EXCEPTION in a trigger or an RPC arrives as P0001 with the
      // raised text as the message — so `dm_not_accepted` from the DM gate's
      // trigger would otherwise reach callers as the code "P0001", which no
      // caller can act on. The migrations raise bare snake_case tokens by
      // convention (`quota_exceeded`, `not_a_member`, `not_authenticated`), so
      // one that looks like a token is passed through as the code, matching
      // what the central tier already returns for the same wall.
      if (e.code == 'P0001' && _raisedCode.hasMatch(message)) {
        return APIResponse(success: false, error: message, errorCode: message);
      }
      // 42501 is Postgres' "permission denied" — a policy or a column grant
      // said no. It reaches the user as a plain refusal, not a retry.
      return APIResponse(success: false, error: message, errorCode: e.code);
    } on StorageException catch (e) {
      return APIResponse(
        success: false,
        error: e.message,
        errorCode: e.statusCode,
      );
    } on TimeoutException {
      return APIResponse.error(
        "This server isn't responding — it may be offline. Try again later.",
        errorCode: ErrorCode.serverTimeout,
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final unreachable =
          msg.contains('socketexception') ||
          msg.contains('clientexception') ||
          msg.contains('failed host lookup') ||
          msg.contains('connection refused') ||
          msg.contains('connection closed') ||
          msg.contains('network is unreachable');
      if (unreachable) {
        return APIResponse.error(
          "Can't reach this server. It may be offline, or check your connection.",
          errorCode: ErrorCode.serverUnreachable,
        );
      }
      return APIResponse.error(e);
    }
  }

  void dispose() {
    for (final c in _clients.values) {
      unawaited(c.dispose());
    }
    _clients.clear();
  }
}

/// One call's way into a cached client, carrying that call's token.
///
/// A query copies the client's headers when it is built, so the token is set
/// right then, in the same synchronous step. Until Nov 21 it was set once,
/// when the call began, and a query built after an `await` could carry
/// whatever token was set last: another server's, when two servers share a
/// project. Under that server's policies a write matches no rows and raises
/// nothing, so a chat key could be reported published that never was, and
/// nobody could seal that member a channel key until the app restarted
/// (found by reading the code, not seen).
class ServerDbClient {
  final SupabaseClient _client;
  final Map<String, String> _headers;

  const ServerDbClient._(this._client, this._headers);

  SupabaseQueryBuilder from(String table) {
    _client.headers = _headers;
    return _client.from(table);
  }

  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    bool get = false,
  }) {
    _client.headers = _headers;
    return _client.rpc(fn, params: params, get: get);
  }
}
