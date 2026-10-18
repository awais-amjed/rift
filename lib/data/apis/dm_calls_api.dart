import '../classes/api_response.dart';
import '../classes/server.dart';
import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';

/// Calls between two members, on one server: ringing, answering, hanging up,
/// and asking what is still ringing.
///
/// A call rings on whichever server it was placed on, and the person
/// answering may be looking at another, so `DmCallCubit` builds one for the
/// call's server rather than the one on screen.
///
/// The token to join the call's room is not here. It is measured against the
/// server's voice regions like a channel's, so it stays with the channel
/// token in `VoiceApi`.
///
/// Holds nothing, so a widget that needs one builds it from the session.
class DmCallsApi {
  final ServerSession _target;

  DmCallsApi(this._target);

  ServerRepository get _repository => _target.session.repository;

  String _keyOf(Server server) => server.supabaseKey ?? '';

  Future<APIResponse> startDmCall(String peerId) => _target.call(
    (server, token) => _repository.startDmCall(
      server.supabaseUrl,
      anonKey: _keyOf(server),
      bearerToken: token,
      peerId: peerId,
    ),
  );

  Future<APIResponse> answerDmCall(String callId) => _target.call(
    (server, token) => _repository.answerDmCall(
      server.supabaseUrl,
      anonKey: _keyOf(server),
      bearerToken: token,
      callId: callId,
    ),
  );

  Future<APIResponse> endDmCall(String callId) => _target.call(
    (server, token) => _repository.endDmCall(
      server.supabaseUrl,
      anonKey: _keyOf(server),
      bearerToken: token,
      callId: callId,
    ),
  );

  Future<APIResponse> dmCallAlive(String callId) => _target.call(
    (server, token) => _repository.dmCallAlive(
      server.supabaseUrl,
      anonKey: _keyOf(server),
      bearerToken: token,
      callId: callId,
    ),
  );

  Future<APIResponse> myDmCalls({List<String> known = const []}) =>
      _target.call(
        (server, token) => _repository.myDmCalls(
          server.supabaseUrl,
          anonKey: _keyOf(server),
          bearerToken: token,
          known: known,
        ),
      );

  Future<APIResponse> dmCallLog({required String peerId, DateTime? since}) =>
      _target.call(
        (server, token) => _repository.dmCallLog(
          server.supabaseUrl,
          anonKey: _keyOf(server),
          bearerToken: token,
          peerId: peerId,
          since: since,
        ),
      );
}
