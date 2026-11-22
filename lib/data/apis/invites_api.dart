import '../classes/server_invite.dart';
import '../repositories/server_pass_repository.dart';
import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';

/// Invite links: making one for a server, listing them, and throwing one away.
/// Reading one before joining is `JoiningApi`'s, since there is no server to
/// be on yet.
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
    bool needsAccount = false,
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
        needsAccount: needsAccount,
      ),
    );

    if (!response.success) {
      return (
        success: false,
        inviteCode: null,
        error:
            inviteErrorText(response.error, needsAccount: needsAccount) ??
            'Failed to generate invite',
      );
    }
    final inviteCode = response.data['invite_code'] as String;
    return (success: true, inviteCode: inviteCode, error: null);
  }

  /// Mark or unmark one of this server's links as needing a Rift account.
  /// Admins only; the server refuses anybody else.
  Future<({bool success, String? error})> setNeedsAccount({
    required String inviteCode,
    required bool needsAccount,
  }) async {
    final server = _target.server;
    if (server == null) return (success: false, error: ServerSession.gone);
    final response = await _session.callFor(
      server,
      (token) => _repository.setInviteNeedsAccount(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        inviteCode: inviteCode,
        needsAccount: needsAccount,
        bearerToken: token,
      ),
    );
    final reason = response.success && response.data is Map
        ? (response.data as Map)['reason']
        : null;
    if (reason == 'ok') return (success: true, error: null);
    return (
      success: false,
      error: reason == 'not_admin'
          ? 'Only an admin can change this.'
          : response.error ?? "Couldn't change the link.",
    );
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

  /// The server's links, newest first: every one for an administrator, a
  /// member's own otherwise (and an administrator's own on a server from
  /// before Nov 22 2026). Null on failure, so a page can tell "none" from
  /// "could not read them".
  Future<List<ServerInvite>?> listInvites() async {
    final server = _target.server;
    if (server == null) return null;
    final response = await _session.callFor(
      server,
      (token) => _repository.listInvites(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      ),
    );
    if (!response.success) return null;
    final rows =
        (response.data as Map<String, dynamic>)['invites'] as List? ?? const [];
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        ServerInvite.fromJson(r),
    ];
  }

  /// Revoke one listed link. No row removed is a refusal, said as one.
  Future<({bool success, String? error})> revoke(String inviteId) async {
    final server = _target.server;
    if (server == null) return (success: false, error: ServerSession.gone);
    final response = await _session.callFor(
      server,
      (token) => _repository.revokeInvite(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        inviteId: inviteId,
      ),
    );
    if (!response.success) {
      return (
        success: false,
        error: response.error ?? "Couldn't revoke that link.",
      );
    }
    final deleted = (response.data as Map?)?['deleted'] == true;
    return (
      success: deleted,
      error: deleted
          ? null
          : "That link wasn't revoked. It may be used up or gone already.",
    );
  }
}
