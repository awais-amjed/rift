import 'dart:async';

import 'package:supabase/supabase.dart' hide ErrorCode;

import '../classes/api_response.dart';
import '../enums/error_code.dart';

/// Authenticated PostgREST access to a self-hosted server's database.
///
/// Most of what the client does is now an ordinary table call under the
/// policies in `002_security.sql` rather than an edge function. That is only
/// safe because those policies exist: before them the anon key — which every
/// member holds — could read and delete every message on a server, so "clients
/// never touch tables" was a convention, not a boundary.
///
/// One client per (url, key) is cached: a `SupabaseClient` is cheap but not
/// free, and a server is talked to over and over. The bearer token is re-set on
/// each call because it rotates underneath us — a silent SIWS re-login hands
/// back a new JWT and the next call must carry it.
class ServerDb {
  final Map<String, SupabaseClient> _clients = {};

  SupabaseClient client(String url, String anonKey, String? bearerToken) {
    final db = _clients.putIfAbsent('$url|$anonKey', () {
      return SupabaseClient(url, anonKey);
    });
    db.headers = {
      'apikey': anonKey,
      if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
    };
    return db;
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
      if (e.code == 'PGRST301' ||
          message.contains('JWT') ||
          message.contains('expired')) {
        return APIResponse(
          success: false,
          error: message,
          errorCode: ErrorCode.tokenExpired,
        );
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
