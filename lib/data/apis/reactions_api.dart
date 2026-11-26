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

  /// Who is reacting, so a ring naming them can be told from anybody else's.
  String? get callerId => _target.server?.user?.id;

  /// A refused toggle, in words.
  static String failureOf(APIResponse response) => switch (response.errorCode) {
    'too_many_reactions' => 'A message can have at most 20 different reactions',
    _ => 'Failed to react',
  };

  /// The counts a toggle answered, as `{reactions: {id: counts}}` the way
  /// [listReactions] answers them, or null from a server that answers none.
  static Map<String, dynamic>? countsOf(APIResponse response, int messageId) {
    final data = response.data;
    if (!response.success || data is! Map || !data.containsKey('counts')) {
      return null;
    }
    return {
      'reactions': {'$messageId': data['counts']},
    };
  }

  /// Toggle the caller's [emoji] reaction on a message. From a server with
  /// `toggle_reaction` (self-host 067) the answer carries the counts after
  /// it ([countsOf]).
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
