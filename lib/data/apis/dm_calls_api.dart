import '../classes/api_response.dart';
import '../classes/server.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';

/// Calls between two members, on a **named** server: ringing, answering,
/// hanging up, and asking what is still ringing.
///
/// Named rather than selected, every one of them: a call rings on whichever
/// server it was placed on, and the person answering may be looking at
/// another. Reading the selection here is how an answer would end up sent to
/// the wrong database.
///
/// The token to join the call's room is not here. It is measured against the
/// server's voice regions like a channel's, so it stays with the channel
/// token in `ServerCubit` until voice moves out too.
///
/// Holds nothing, so a widget that needs one builds it from the session.
class DmCallsApi {
  final SessionRepository _session;

  DmCallsApi({required SessionRepository session}) : _session = session;

  ServerRepository get _repository => _session.repository;

  String _keyOf(Server server) => server.supabaseKey ?? '';

  Future<APIResponse> startDmCall(Server server, String peerId) =>
      _session.callFor(
        server,
        (token) => _repository.startDmCall(
          server.supabaseUrl,
          anonKey: _keyOf(server),
          bearerToken: token,
          peerId: peerId,
        ),
      );

  Future<APIResponse> answerDmCall(Server server, String callId) =>
      _session.callFor(
        server,
        (token) => _repository.answerDmCall(
          server.supabaseUrl,
          anonKey: _keyOf(server),
          bearerToken: token,
          callId: callId,
        ),
      );

  Future<APIResponse> endDmCall(Server server, String callId) =>
      _session.callFor(
        server,
        (token) => _repository.endDmCall(
          server.supabaseUrl,
          anonKey: _keyOf(server),
          bearerToken: token,
          callId: callId,
        ),
      );

  Future<APIResponse> dmCallAlive(Server server, String callId) =>
      _session.callFor(
        server,
        (token) => _repository.dmCallAlive(
          server.supabaseUrl,
          anonKey: _keyOf(server),
          bearerToken: token,
          callId: callId,
        ),
      );

  Future<APIResponse> myDmCalls(
    Server server, {
    List<String> known = const [],
  }) => _session.callFor(
    server,
    (token) => _repository.myDmCalls(
      server.supabaseUrl,
      anonKey: _keyOf(server),
      bearerToken: token,
      known: known,
    ),
  );

  Future<APIResponse> dmCallLog(
    Server server, {
    required String peerId,
    DateTime? since,
  }) => _session.callFor(
    server,
    (token) => _repository.dmCallLog(
      server.supabaseUrl,
      anonKey: _keyOf(server),
      bearerToken: token,
      peerId: peerId,
      since: since,
    ),
  );
}
