import '../classes/api_response.dart';
import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';

/// A server's own DMs: sealed envelopes between two members of it, stored on
/// that server like channel messages are.
///
/// Holds nothing, so a widget that needs one builds it from the session.
class DmsApi {
  final ServerSession _target;

  DmsApi(this._target);

  SessionRepository get _session => _target.session;

  ServerRepository get _repository => _session.repository;

  /// Replace one server-DM envelope (sender only).
  Future<APIResponse> editDm({
    required int messageId,
    required Map<String, dynamic> envelope,
  }) => _target.call(
    (server, token) => _repository.editDm(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      messageId: messageId,
      envelope: envelope,
      bearerToken: token,
    ),
  );

  /// Hard-delete one server DM (sender only).
  Future<APIResponse> deleteDm({required int messageId}) => _target.call(
    (server, token) => _repository.deleteDm(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      messageId: messageId,
      bearerToken: token,
    ),
  );

  /// Store one E2E DM envelope for [recipientId].
  ///
  /// A server with no key yet is refused here rather than sent with an empty
  /// one: the envelope was sealed for that server, and must not land
  /// anywhere else.
  Future<APIResponse> sendDm({
    required String recipientId,
    required Map<String, dynamic> envelope,
  }) async {
    final server = _target.server;
    final anonKey = server?.supabaseKey;
    if (server == null || anonKey == null) {
      return APIResponse.error(ServerSession.gone);
    }
    return _session.callFor(
      server,
      (token) => _repository.sendDm(
        server.supabaseUrl,
        anonKey: anonKey,
        recipientId: recipientId,
        envelope: envelope,
        bearerToken: token,
      ),
    );
  }

  /// Page through the DM conversation with [peerId].
  Future<APIResponse> listDms({
    required String peerId,
    int? beforeId,
    int? afterId,
    int? limit,
  }) => _target.call(
    (server, token) => _repository.listDms(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      userId: server.user?.id ?? '',
      peerId: peerId,
      beforeId: beforeId,
      afterId: afterId,
      limit: limit,
      bearerToken: token,
    ),
  );

  /// Re-read one server DM after a change doorbell named it. Answers
  /// `{message: …}`, or `{message: null}` when the row has been deleted.
  Future<APIResponse> getDmMessage({required int messageId}) => _target.call(
    (server, token) => _repository.getDm(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      userId: server.user?.id ?? '',
      messageId: messageId,
      bearerToken: token,
    ),
  );

  /// One page of the local user's DM conversations, newest activity first.
  ///
  /// [before] is the cursor: the newest message id of the last row already
  /// held. Null asks for the top.
  Future<APIResponse> listDmConversations({int? before}) => _target.call(
    (server, token) => _repository.listDmConversations(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      before: before,
    ),
  );
}
