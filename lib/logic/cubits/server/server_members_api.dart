part of 'server_cubit.dart';

/// The people on a server: the roster, the cache behind it, and the two writes
/// that change what one of them may do.
///
/// Split out of `_ServerApiMixin` because these four share a shape the rest of
/// that file doesn't: they are the calls a dialog opens for a server other than
/// the one on screen (the rail's Manage members), so each one names its server
/// and the cache under them is keyed by server too. Keeping them together is
/// what makes that shape visible instead of incidental.
mixin _ServerMembersApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;

  Future<APIResponse> _callFor(
    Server server,
    Future<APIResponse> Function(String token) call,
  );

  /// Implemented by [ServerCubit] — see its doc for why a named server never
  /// falls back to the selected one.
  Server? _target(String? serverId);
  String _noTarget(String? serverId);

  /// [_noTarget] as the failed [APIResponse] the plain endpoints return.
  APIResponse _noTargetResponse(String? serverId) =>
      APIResponse.error(_noTarget(serverId));

  /// Last fetched member lists, `serverId → userId → member` — warmed by
  /// [listMembers].
  ///
  /// Lets any surface resolve a user id to their profile (notably
  /// `chat_public_key`, needed to open a DM) without another round trip. Not
  /// authoritative: [findMember] refetches on a miss.
  ///
  /// Keyed by server because a user id only means something on the server it
  /// came from — and because listing another server's members would otherwise
  /// evict the entries the chat surfaces are about to ask for.
  final Map<String, Map<String, ServerMember>> _memberCache = {};

  /// A member by user id, fetching the list once if we haven't got them.
  /// Null when they aren't a member of that server.
  Future<ServerMember?> findMember(String userId, {String? serverId}) async {
    final id = _target(serverId)?.id;
    if (id == null) return null;

    final cached = _memberCache[id]?[userId];
    if (cached != null) return cached;
    final result = await listMembers(serverId: id);
    if (!result.success) return null;
    return _memberCache[id]?[userId];
  }

  /// Fetch the full member list for [serverId], or for the selected server.
  Future<({bool success, List<ServerMember>? members, String? error})>
  listMembers({String? serverId}) async {
    final server = _target(serverId);
    if (server == null) {
      return (success: false, members: null, error: _noTarget(serverId));
    }

    final response = await _callFor(
      server,
      (token) => _repository.listUsers(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      ),
    );

    if (!response.success) {
      return (
        success: false,
        members: null,
        error: response.error ?? 'Failed to load members',
      );
    }

    final members = ((response.data['users'] as List<dynamic>?) ?? [])
        .map((u) => ServerMember.fromJson(u as Map<String, dynamic>))
        .toList();
    _memberCache[server.id] = {for (final m in members) m.id: m};
    return (success: true, members: members, error: null);
  }

  /// Set a member's permission flags on [serverId], or on the selected server
  /// (server admin only).
  Future<APIResponse> setUserPermissions({
    required String userId,
    bool? isServerAdmin,
    bool? isChannelManager,
    bool? canCreateTokens,
    String? serverId,
  }) {
    final server = _target(serverId);
    if (server == null) return Future.value(_noTargetResponse(serverId));

    return _callFor(
      server,
      (token) => _repository.setUserPermissions(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        userId: userId,
        isServerAdmin: isServerAdmin,
        isChannelManager: isChannelManager,
        canCreateTokens: canCreateTokens,
      ),
    );
  }

  /// Persistently mutes/deafens a user server-wide on [serverId], or on the
  /// selected server (requires channel manager or server admin).
  Future<APIResponse> moderateUser({
    required String userId,
    bool? isMuted,
    bool? isDeafened,
    String? serverId,
  }) {
    final server = _target(serverId);
    if (server == null) return Future.value(_noTargetResponse(serverId));

    return _callFor(
      server,
      (token) => _repository.moderateUser(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        userId: userId,
        isMuted: isMuted,
        isDeafened: isDeafened,
      ),
    );
  }
}
