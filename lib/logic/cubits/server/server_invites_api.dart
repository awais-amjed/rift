part of 'server_cubit.dart';

/// Invite links: making one for a server, and reading one before joining.
mixin _ServerInvitesApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;

  Future<APIResponse> _callFor(
    Server server,
    Future<APIResponse> Function(String token) call,
  );

  Server? _target(String? serverId);
  String _noTarget(String? serverId);

  Future<({bool success, String? inviteCode, String? error})> createInvite({
    int? maxUses = 1,
    int? expiresInSeconds,
    String? serverId,
    bool isBot = false,
    String? roleId,
  }) async {
    final server = _target(serverId);
    if (server == null) {
      return (success: false, inviteCode: null, error: _noTarget(serverId));
    }

    final response = await _callFor(
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

    if (response.success) {
      final inviteCode = response.data['invite_code'] as String;
      return (success: true, inviteCode: inviteCode, error: null);
    } else {
      return (
        success: false,
        inviteCode: null,
        error: response.error ?? 'Failed to generate invite',
      );
    }
  }

  /// Read an invite link and ask its server what it opens, without using it.
  ///
  /// The first of the two join steps. A link that does not parse is refused
  /// here, in words; one that parses is put to the server, which answers with
  /// the name — or with why not, which is the same answer registration would
  /// have given a screen later, after a username had been typed for nothing.
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
