import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';

/// Invite links: making one for a server, and throwing one away. Reading one
/// before joining is `JoiningApi`'s, since there is no server to be on yet.
///
/// Holds nothing, so a widget builds one from the session.
class InvitesApi {
  final ServerSession _target;

  InvitesApi(this._target);

  SessionRepository get _session => _target.session;

  ServerRepository get _repository => _session.repository;

  Future<({bool success, String? inviteCode, String? error})> createInvite({
    int? maxUses = 1,
    int? expiresInSeconds,
    bool isBot = false,
    String? roleId,
  }) async {
    final server = _target.server;
    if (server == null) {
      return (success: false, inviteCode: null, error: ServerSession.gone);
    }

    final response = await _session.callFor(
      server,
      (token) => _repository.createInvite(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        serverId: server.id,
        userId: server.user?.id ?? '',
        bearerToken: token,
        maxUses: maxUses,
        expiresInSeconds: expiresInSeconds,
        isBot: isBot,
        roleId: roleId,
      ),
    );

    if (!response.success) {
      return (
        success: false,
        inviteCode: null,
        error: response.error ?? 'Failed to generate invite',
      );
    }
    final inviteCode = response.data['invite_code'] as String;
    return (success: true, inviteCode: inviteCode, error: null);
  }

  /// Throw away an invite this account minted.
  ///
  /// Best effort and deliberately quiet: the callers are failure paths that
  /// already have something to say, and "the listing failed, and so did
  /// tidying up after it" is not a second thing to put in front of somebody.
  Future<void> revokeInvite({required String inviteCode}) async {
    final server = _target.server;
    if (server == null) return;
    await _session.callFor(
      server,
      (token) => _repository.deleteInvite(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        inviteCode: inviteCode,
        bearerToken: token,
      ),
    );
  }
}
