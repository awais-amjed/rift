import '../classes/api_response.dart';
import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';

/// Reactions on one server's messages, in channels and in DMs alike:
/// [scope] (`channel` or `dm`) picks the table, and who may react is a policy.
///
/// Not E2E — the server sees who reacted with what (ARCHITECTURE.md §4). The
/// chat cubits hold the counts and merge what these answer.
///
/// Holds nothing, so a widget that needs one builds it from the session.
class ReactionsApi {
  final ServerSession _target;

  ReactionsApi(this._target);

  SessionRepository get _session => _target.session;

  ServerRepository get _repository => _session.repository;

  /// Toggle the caller's [emoji] reaction on a message.
  Future<APIResponse> toggleReaction({
    required String scope,
    required int messageId,
    required String emoji,
  }) => _target.call(
    (server, token) => _repository.toggleReaction(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      userId: server.user?.id ?? '',
      scope: scope,
      messageId: messageId,
      emoji: emoji,
      bearerToken: token,
    ),
  );

  /// Aggregated reactions for a set of loaded messages.
  Future<APIResponse> listReactions({
    required String scope,
    required List<int> messageIds,
  }) => _target.call(
    (server, token) => _repository.listReactions(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      userId: server.user?.id ?? '',
      scope: scope,
      messageIds: messageIds,
      bearerToken: token,
    ),
  );
}
