import '../classes/api_response.dart';
import '../classes/server.dart';
import 'session_repository.dart';

/// One joined server, as every call to it sees it: [SessionRepository] with
/// the server already chosen.
///
/// Every class in `data/apis` takes one, so no call can fall back on
/// whichever server is on screen. That fallback is how a call kept running on
/// one server sent its work to the server being read, and how a dialog about
/// one server wrote to another. The server is looked up by id on each call, so
/// the token a re-login just wrote is the one used, and a server left in the
/// meantime answers [gone] instead of acting.
class ServerSession {
  final SessionRepository session;
  final String serverId;

  const ServerSession(this.session, this.serverId);

  /// The server as the list now holds it, or null once it has been left.
  Server? get server => session.serverById(serverId);

  /// What a call says when [server] is gone.
  static const gone = 'That server is no longer on this device';

  /// [SessionRepository.callFor] against this server, with its token.
  Future<APIResponse> call(
    Future<APIResponse> Function(Server server, String token) call,
  ) {
    final server = this.server;
    if (server == null) return Future.value(APIResponse.error(gone));
    return session.callFor(server, (token) => call(server, token));
  }

  @override
  bool operator ==(Object other) =>
      other is ServerSession &&
      identical(other.session, session) &&
      other.serverId == serverId;

  @override
  int get hashCode => Object.hash(identityHashCode(session), serverId);
}
