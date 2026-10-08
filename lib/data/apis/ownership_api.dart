import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';

/// The owner's two calls: hand the server on, or end it.
///
/// Neither touches the local list beyond what the server says back. A transfer
/// re-reads our own standing ([SessionRepository.refreshDetails]); the caller
/// rings the server's doorbell, because the new owner is the one person this
/// has to reach at once. A delete leaves forgetting the server to the caller,
/// once the server has said yes.
///
/// Holds nothing, so a widget builds one from the session.
class OwnershipApi {
  final SessionRepository _session;

  OwnershipApi({required SessionRepository session}) : _session = session;

  ServerRepository get _repository => _session.repository;

  /// Hand [serverId], or the selected server, to [userId]. We stay an admin;
  /// they become the one person who can do this next.
  Future<({bool success, String? error})> transferOwnership(
    String userId, {
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) {
      return (success: false, error: _session.noTarget(serverId));
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

  /// End [serverId], or the selected server, for everybody.
  ///
  /// The server side is what decides — only the owner gets past the RPC — so
  /// the caller forgets the server only once this has said yes. Other members
  /// find out the way they find out about any server that stops answering.
  Future<({bool success, String? error})> deleteServer({
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) {
      return (success: false, error: _session.noTarget(serverId));
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
