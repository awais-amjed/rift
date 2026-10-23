import '../classes/api_response.dart';
import '../enums/notification_level.dart';
import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';

/// One server's unread badges: the counts, the read cursors behind them, and
/// how much each conversation may interrupt.
///
/// Here rather than on the notifications cubit's own Realtime client, so a
/// call refused for an expired session signs in again and is tried once more,
/// as every other server call is. The cubit only re-read when the next event
/// or the minute's sweep came round.
///
/// Holds nothing, so a cubit builds one for the server it is about.
class UnreadApi {
  final ServerSession _target;

  UnreadApi(this._target);

  SessionRepository get _session => _target.session;

  ServerRepository get _repository => _session.repository;

  // ── Badges ──────────────────────────────────────────────

  /// `{channels, dms, prefs}`: what is unread, and the levels that decide
  /// whether it may interrupt.
  Future<APIResponse> unreadCounts() => _target.call(
    (server, token) => _repository.unreadCounts(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
    ),
  );

  /// Move the cursor for one channel or conversation (`channel` or `dm`) to
  /// what is newest right now.
  Future<APIResponse> markRead({
    required String scope,
    required String scopeId,
  }) => _target.call(
    (server, token) => _repository.markRead(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      scope: scope,
      scopeId: scopeId,
    ),
  );

  /// Mark the whole server read, channels and conversations alike.
  Future<APIResponse> markAllRead() => _target.call(
    (server, token) => _repository.markAllRead(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
    ),
  );

  // ── Levels ──────────────────────────────────────────────

  /// Store [level] for [scope] (`server`, `channel` or `dm`) and [scopeId].
  Future<APIResponse> setLevel({
    required String scope,
    required String scopeId,
    required NotificationLevel level,
  }) => _target.call(
    (server, token) => _repository.setNotificationLevel(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      userId: server.user?.id ?? '',
      scope: scope,
      scopeId: scopeId,
      level: level.toJson(),
    ),
  );

  /// Remove the stored level for [scope] and [scopeId].
  Future<APIResponse> clearLevel({
    required String scope,
    required String scopeId,
  }) => _target.call(
    (server, token) => _repository.clearNotificationLevel(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      userId: server.user?.id ?? '',
      scope: scope,
      scopeId: scopeId,
    ),
  );
}
