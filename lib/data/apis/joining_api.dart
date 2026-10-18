import '../classes/resolved_invite.dart';
import '../invite_link.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';

/// The calls made before there is a server to be signed in to: creating one,
/// and reading an invite link before joining.
///
/// Apart from every other class here, which is bound to a joined server
/// (`ServerSession`), because these have none yet.
///
/// Holds nothing, so a widget builds one from the session.
class JoiningApi {
  final SessionRepository _session;

  JoiningApi(this._session);

  ServerRepository get _repository => _session.repository;

  /// Creates a new server. On success returns the single-use admin invite code.
  ///
  /// The one call here made on the operator's service key rather than a
  /// session: there is no server to be signed in to yet.
  Future<({bool success, String? inviteCode, String? error})> createServer({
    required String supabaseUrl,
    required String serviceKey,
    required String name,
    String? iconUrl,
    required String livekitUrl,
    required String livekitApiKey,
    required String livekitSecretKey,
  }) async {
    final response = await _repository.createServer(
      supabaseUrl,
      serviceKey: serviceKey,
      name: name,
      iconUrl: iconUrl,
      livekitUrl: livekitUrl,
      livekitApiKey: livekitApiKey,
      livekitSecretKey: livekitSecretKey,
    );

    if (!response.success) {
      return (success: false, inviteCode: null, error: response.error);
    }

    final data = response.data as Map<String, dynamic>;
    final inviteCode = data['invite_code'] as String;
    return (success: true, inviteCode: inviteCode, error: null);
  }

  /// Read an invite link and ask its server what it opens, without using it.
  ///
  /// The first of the two join steps, and needs no session: the person is not
  /// on that server yet. A link that does not parse is refused here, in words;
  /// one that parses is put to the server, which answers with the name — or
  /// with why not, which is the same answer registration would have given a
  /// screen later, after a username had been typed for nothing.
  Future<({ResolvedInvite? invite, String? error})> resolveInvite(
    String rawLink,
  ) async {
    final link = InviteLink.parse(rawLink);
    if (link == null) {
      return (
        invite: null,
        error:
            "That doesn't look like a complete invite link. Ask the server "
            'admin for a new one.',
      );
    }
    final resolved = await _repository.resolveInvite(
      link.serverUrl,
      link.inviteCode,
    );
    if (!resolved.success || resolved.serverId == null) {
      return (
        invite: null,
        error: resolved.error ?? 'That invite cannot be used any more.',
      );
    }
    return (
      invite: ResolvedInvite(
        serverUrl: link.serverUrl,
        inviteCode: link.inviteCode,
        serverId: resolved.serverId!,
        serverName: resolved.serverName ?? link.serverUrl,
      ),
      error: null,
    );
  }
}
