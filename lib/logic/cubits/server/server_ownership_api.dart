part of 'server_cubit.dart';

mixin _ServerOwnershipApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;

  Future<APIResponse> _callFor(
    Server server,
    Future<APIResponse> Function(String token) call,
  );
  Server? _target(String? serverId);
  String _noTarget(String? serverId);

  Future<({bool success, String? error})> refreshServerDetails({
    String? serverId,
  });
  void removeServer(String serverId);
  void Function(String serverId)? get _onServerEvent;

  /// Hand [serverId], or the selected server, to [userId]. We stay an admin;
  /// they become the one person who can do this next.
  Future<({bool success, String? error})> transferOwnership(
    String userId, {
    String? serverId,
  }) async {
    final server = _target(serverId);
    if (server == null) return (success: false, error: _noTarget(serverId));

    final response = await _callFor(
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
    // roles screen decides on. The new owner's row changed too, and they are
    // the one person this has to reach at once — the doorbell is what makes
    // every other client re-read its standing.
    await refreshServerDetails(serverId: server.id);
    _onServerEvent?.call(server.id);
    return (success: true, error: null);
  }

  /// End [serverId], or the selected server, for everybody, then forget it
  /// here.
  ///
  /// The server side is what decides — only the owner gets past the RPC — so
  /// the local list is only touched once it has said yes. Other members find
  /// out the way they find out about any server that stops answering.
  Future<({bool success, String? error})> deleteServer({
    String? serverId,
  }) async {
    final server = _target(serverId);
    if (server == null) return (success: false, error: _noTarget(serverId));

    final response = await _callFor(
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
    removeServer(server.id);
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
