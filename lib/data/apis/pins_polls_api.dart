import '../classes/api_response.dart';
import '../classes/server.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';

/// Pins and polls on the selected server. Pass-throughs — the chat cubits
/// hold the state, decrypt the pinned rows, and merge the tallies.
///
/// Holds nothing, so a widget that needs one builds it from the session.
class PinsPollsApi {
  final SessionRepository _session;

  PinsPollsApi({required SessionRepository session}) : _session = session;

  ServerRepository get _repository => _session.repository;

  /// [call] against the selected server.
  Future<APIResponse> _onSelected(
    Future<APIResponse> Function(Server server, String token) call,
  ) async {
    final server = _session.selectedServer;
    if (server == null) return APIResponse.error(_session.noTarget(null));
    return _session.callFor(server, (token) => call(server, token));
  }

  // ── Pins ──────────────────────────────────────────────────

  /// Pin or unpin a message ([scope] is `channel` or `dm`).
  Future<APIResponse> setPinned({
    required String scope,
    required int messageId,
    required bool pinned,
  }) => _onSelected(
    (server, token) => _repository.setPinned(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      scope: scope,
      messageId: messageId,
      pinned: pinned,
    ),
  );

  /// A channel's pinned message rows, newest pin first.
  Future<APIResponse> listChannelPins({required String channelId}) =>
      _onSelected(
        (server, token) => _repository.listChannelPins(
          server.supabaseUrl,
          anonKey: server.supabaseKey ?? '',
          userId: server.user?.id ?? '',
          bearerToken: token,
          channelId: channelId,
        ),
      );

  /// The pinned rows of the server DM with [peerId], newest pin first.
  Future<APIResponse> listDmPins({required String peerId}) => _onSelected(
    (server, token) => _repository.listDmPins(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      userId: server.user?.id ?? '',
      bearerToken: token,
      peerId: peerId,
    ),
  );

  // ── Polls ─────────────────────────────────────────────────

  /// Tallies for the polls among [messageIds].
  Future<APIResponse> pollTallies({required List<int> messageIds}) =>
      _onSelected(
        (server, token) => _repository.pollTallies(
          server.supabaseUrl,
          anonKey: server.supabaseKey ?? '',
          bearerToken: token,
          messageIds: messageIds,
        ),
      );

  /// Replace the caller's ballot on a poll; answers with the new tally.
  Future<APIResponse> votePoll({
    required int messageId,
    required List<int> options,
  }) => _onSelected(
    (server, token) => _repository.votePoll(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      messageId: messageId,
      options: options,
    ),
  );

  /// End a poll now (its author only).
  Future<APIResponse> closePoll({required int messageId}) => _onSelected(
    (server, token) => _repository.closePoll(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      messageId: messageId,
    ),
  );
}
