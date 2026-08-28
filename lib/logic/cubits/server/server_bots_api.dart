part of 'server_cubit.dart';

/// The one bot capability that is not arranged around a bot never holding a
/// key (BOTS.md §6).
///
/// Split from the webhook API next door because they are opposites wearing the
/// same shape: a webhook is a thing that can *write* into a channel without
/// being a member, and this is a thing that can *read* one. The second is the
/// only place in Rift where a decision cannot be undone — a key that has been
/// unwrapped stays unwrapped — so it keeps its own file and its own comments.
mixin _ServerBotsApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  String get _anonKey;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  /// Hand a bot the key to a channel, or take it back.
  ///
  /// Every rule behind this is in the database and none of it is repeated here
  /// — the permission, the channel being one the caller can see, the version
  /// the grant starts at, and the notice it leaves in the channel. What comes
  /// back is a reason, which is the only part a client has to translate.
  Future<({bool success, String? error})> setBotChannelKey({
    required String channelId,
    required String botId,
    required bool granted,
  }) async {
    final server = state.selectedServer;
    if (server == null) return (success: false, error: 'No server');

    final response = await _callWithAutoRefresh(
      (token) => _repository.setBotChannelKey(
        server.supabaseUrl,
        anonKey: _anonKey,
        bearerToken: token,
        channelId: channelId,
        botId: botId,
        granted: granted,
      ),
    );
    if (!response.success) {
      return (success: false, error: response.error ?? 'Could not do that');
    }

    final reason = (response.data as Map<String, dynamic>?)?['reason'];
    if (reason != 'ok' && reason != 'already_granted') {
      return (success: false, error: _grantFailure(reason as String?));
    }
    return (success: true, error: null);
  }

  static String _grantFailure(String? reason) => switch (reason) {
    'forbidden' => 'You cannot give bots access to channels here',
    'no_such_channel' => 'That channel is gone, or is not one you are in',
    'no_such_bot' => 'That bot is not on this server any more',
    _ => 'Could not change that bot’s access',
  };

  /// The ids of the bots holding a key to [channelId].
  ///
  /// Separate from [channelListeners], which is the same query answered for a
  /// different audience: that one is names for a chip every member reads, this
  /// one is ids for the dialog that changes them.
  Future<Set<String>> channelListenerIds(String channelId) async {
    final server = state.selectedServer;
    if (server == null) return const {};

    final response = await _callWithAutoRefresh(
      (token) => _repository.listChannelListeners(
        server.supabaseUrl,
        anonKey: _anonKey,
        bearerToken: token,
        channelId: channelId,
      ),
    );
    if (!response.success) return const {};

    final rows =
        (response.data as Map<String, dynamic>)['listeners'] as List? ??
        const [];
    return {
      for (final r in rows.cast<Map<String, dynamic>>()) r['bot_id'] as String,
    };
  }

  /// The bots holding a key to [channelId], by display name.
  ///
  /// Read on channel open and shown in the header, not behind a menu: a
  /// standing marker is the point (BOTS.md §6, rule 4). A dialog somebody has
  /// to go looking for tells the people who already knew.
  Future<List<String>> channelListeners(String channelId) async {
    final server = state.selectedServer;
    if (server == null) return const [];

    final response = await _callWithAutoRefresh(
      (token) => _repository.listChannelListeners(
        server.supabaseUrl,
        anonKey: _anonKey,
        bearerToken: token,
        channelId: channelId,
      ),
    );
    if (!response.success) return const [];

    final rows =
        (response.data as Map<String, dynamic>)['listeners'] as List? ??
        const [];
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        (r['display_name'] as String?) ?? (r['username'] as String? ?? 'a bot'),
    ];
  }
}
