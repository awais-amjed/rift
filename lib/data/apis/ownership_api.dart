import '../enums/leave_outcome.dart';
import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';

/// The owner's two calls: hand the server on, or end it. And everybody
/// else's one: leave it.
///
/// Neither touches the local list beyond what the server says back. A transfer
/// re-reads our own standing ([SessionRepository.refreshDetails]); the caller
/// rings the server's doorbell, because the new owner is the one person this
/// has to reach at once. A delete leaves forgetting the server to the caller,
/// once the server has said yes.
///
/// Holds nothing, so a widget builds one from the session.
class OwnershipApi {
  final ServerSession _target;

  OwnershipApi(this._target);

  SessionRepository get _session => _target.session;

  ServerRepository get _repository => _session.repository;

  /// Hand the server to [userId]. We stay an admin;
  /// they become the one person who can do this next.
  Future<({bool success, String? error})> transferOwnership(
    String userId,
  ) async {
    final server = _target.server;
    if (server == null) {
      return (success: false, error: ServerSession.gone);
    }

    final response = await _session.callFor(
      server,
      (token) => _repository.transferOwnership(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        userId: userId,
      ),
    );
    if (!response.success) {
      return (success: false, error: _transferFailure(response.error));
    }
    // Our own row changed under us: the cached owner flag, and the rank every
    // roles screen decides on.
    await _session.refreshDetails(server);
    return (success: true, error: null);
  }

  /// End the server for everybody.
  ///
  /// The server side is what decides — only the owner gets past the RPC — so
  /// the caller forgets the server only once this has said yes. Other members
  /// find out the way they find out about any server that stops answering.
  Future<({bool success, String? error})> deleteServer() async {
    final server = _target.server;
    if (server == null) {
      return (success: false, error: ServerSession.gone);
    }

    final response = await _session.callFor(
      server,
      (token) =>
          _repository.deleteServer(server.supabaseUrl, bearerToken: token),
    );
    if (!response.success) {
      return (
        success: false,
        error: response.error ?? 'Could not delete the server',
      );
    }
    return (success: true, error: null);
  }

  /// Leave the server: a kick by our own hand
  /// (`leave_server`), so we drop off its member list and a new invite
  /// brings us back as ourselves. Forgetting the server is the caller's.
  ///
  /// [LeaveOutcome.unsupported] is a server from before 020, which has no
  /// such call: there, leaving can only ever have meant forgetting it here.
  Future<({LeaveOutcome outcome, String? error})> leaveServer() async {
    final server = _target.server;
    if (server == null) {
      return (outcome: LeaveOutcome.unreachable, error: ServerSession.gone);
    }

    final response = await _session.callFor(
      server,
      (token) => _repository.leaveServer(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      ),
    );
    if (response.success) return (outcome: LeaveOutcome.left, error: null);
    return switch (response.errorCode) {
      'PGRST202' => (outcome: LeaveOutcome.unsupported, error: null),
      'owner_cannot_leave' => (
        outcome: LeaveOutcome.refused,
        error: 'Hand the server to someone else before you leave',
      ),
      _ => (
        outcome: LeaveOutcome.unreachable,
        error: response.error ?? 'Could not leave the server',
      ),
    };
  }

  /// The RPC's reasons, in words. Anything unnamed is passed through.
  static String _transferFailure(String? error) {
    final raw = error ?? 'Could not transfer ownership';
    return switch (raw) {
      _ when raw.contains('not_owner') => 'Only the owner can do this',
      _ when raw.contains('cannot_transfer_to_self') => 'You already own it',
      _ when raw.contains('bot_cannot_own') => 'A bot cannot own a server',
      _ when raw.contains('user_banned') =>
        'A banned member cannot be made owner',
      _ when raw.contains('user_not_found') => 'That member is not here',
      _ => raw,
    };
  }
}
