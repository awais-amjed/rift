part of 'server_cubit.dart';

/// Channel create / update / delete for the selected server.
///
/// Split out of `_ServerApiMixin` because these three share one shape that
/// nothing else in that file does: every one of them mutates the channel list
/// and then has to bring *everyone's* sidebar back in line. That shared tail is
/// [_changeChannel], and keeping it next to its only three callers is the seam.
mixin _ServerChannelsApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  String get _anonKey;

  /// Ping the `server_events` doorbell after a structural change so other
  /// members refresh in realtime. Takes the server it happened on; channels are
  /// only ever created and deleted on the selected one.
  void Function(String serverId)? get _onServerEvent;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  /// Implemented by [_ServerApiMixin].
  Future<({bool success, String? error})> refreshServerDetails();

  /// Create a new channel in the selected server.
  ///
  /// [memberIds] is only read when [isPrivate], and never has to include the
  /// creator: `create_channel` seats them itself (migration 022).
  Future<({bool success, String? error})> createChannel({
    required String name,
    required String channelType,
    bool isPrivate = false,
    List<String> memberIds = const [],
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final response = await _callWithAutoRefresh(
      (token) => _repository.createChannel(
        server.supabaseUrl,
        anonKey: _anonKey,
        bearerToken: token,
        name: name,
        channelType: channelType,
        isPrivate: isPrivate,
        memberIds: isPrivate ? memberIds : const [],
      ),
    );

    if (!response.success) {
      return (
        success: false,
        error: response.error ?? 'Failed to create channel',
      );
    }

    final reason = (response.data as Map<String, dynamic>?)?['reason'];
    if (reason != 'ok') {
      return (success: false, error: _createFailure(reason as String?));
    }

    // Refresh our own channel list to include the newly created one, and ping
    // the server_events doorbell so other members refresh in realtime.
    await refreshServerDetails();
    _onServerEvent?.call(server.id);
    return (success: true, error: null);
  }

  /// Change a channel's name and/or its retention overrides (channel manager
  /// only).
  ///
  /// An override omitted leaves that column alone; the matching `clear…` flag
  /// puts the channel back to inheriting the server's number.
  Future<({bool success, String? error})> updateChannel({
    required String channelId,
    String? name,
    int? retentionDays,
    bool clearRetentionDays = false,
    int? historyCap,
    bool clearHistoryCap = false,
  }) => _changeChannel(
    (server, token) => _repository.updateChannel(
      server.supabaseUrl,
      channelId,
      anonKey: _anonKey,
      bearerToken: token,
      name: name,
      retentionDays: retentionDays,
      clearRetentionDays: clearRetentionDays,
      historyCap: historyCap,
      clearHistoryCap: clearHistoryCap,
    ),
    failure: 'Failed to update channel',
  );

  /// Delete a channel in the selected server (channel manager only). Anyone in
  /// its call is dropped — see [ServerRepository.deleteChannel].
  Future<({bool success, String? error})> deleteChannel(String channelId) =>
      _changeChannel(
        (server, token) => _repository.deleteChannel(
          server.supabaseUrl,
          channelId,
          bearerToken: token,
        ),
        failure: 'Failed to delete channel',
      );

  static String _createFailure(String? reason) => switch (reason) {
    'name_taken' => 'A channel already has that name',
    'not_authorized' => 'You cannot create channels here',
    'bad_name' => 'Give it a name',
    _ => 'Failed to create channel',
  };

  /// Replace a private channel's membership with exactly [userIds].
  ///
  /// Removing the last member deletes the channel, and that is not an accident
  /// to be guarded against here — nobody outside can see a private channel, so
  /// nobody outside could be asked to tidy up an empty one.
  Future<({bool success, String? error})> setChannelMembers({
    required String channelId,
    required List<String> userIds,
  }) => _changeChannel(
    (server, token) => _repository.setChannelMembers(
      server.supabaseUrl,
      channelId,
      anonKey: _anonKey,
      bearerToken: token,
      userIds: userIds,
    ),
    failure: 'Failed to update who is in this channel',
  );

  /// Open a channel up, or close it.
  ///
  /// Closing seats everybody who is currently on the server, so the room does
  /// not empty out under the people already talking in it; narrowing it down is
  /// a second call to [setChannelMembers]. Opening leaves a rotation behind, so
  /// the private history stays unreadable to whoever arrives next.
  Future<({bool success, String? error})> setChannelPrivate({
    required String channelId,
    required bool isPrivate,
  }) => _changeChannel(
    (server, token) => _repository.setChannelPrivate(
      server.supabaseUrl,
      channelId,
      anonKey: _anonKey,
      bearerToken: token,
      isPrivate: isPrivate,
    ),
    failure: isPrivate
        ? 'Failed to make this channel private'
        : 'Failed to open this channel up',
  );

  /// Who is in [channelId], and whether this device may change that.
  ///
  /// Both answers come out of the same rows, which is the reason they are one
  /// call: `can_manage` is a property of *my* membership, and a private
  /// channel's manager is somebody inside it rather than whoever holds
  /// `MANAGE_CHANNELS` on the server — those people cannot see the room at all.
  ///
  /// Empty for a public channel, and for a private one the caller cannot see.
  /// Those are the same answer on purpose.
  Future<({Set<String> memberIds, bool canManage})> channelMembers(
    String channelId,
  ) async {
    final server = state.selectedServer;
    if (server == null) return (memberIds: <String>{}, canManage: false);

    final response = await _callWithAutoRefresh(
      (token) => _repository.listChannelMembers(
        server.supabaseUrl,
        channelId,
        anonKey: _anonKey,
        bearerToken: token,
      ),
    );
    if (!response.success) {
      return (memberIds: <String>{}, canManage: false);
    }

    final rows =
        (response.data as Map<String, dynamic>)['members'] as List? ?? const [];
    final me = server.user?.id;
    return (
      memberIds: {
        for (final r in rows.cast<Map<String, dynamic>>())
          r['user_id'] as String,
      },
      canManage: rows.cast<Map<String, dynamic>>().any(
        (r) => r['user_id'] == me && r['can_manage'] == true,
      ),
    );
  }

  /// Runs a channel mutation, then brings everyone's sidebar in line: our own
  /// list directly, and other members' through the `server_events` doorbell.
  /// They also hear it from Realtime on `channels`; the ping is what makes it
  /// immediate rather than a beat later.
  Future<({bool success, String? error})> _changeChannel(
    Future<APIResponse> Function(Server server, String token) call, {
    required String failure,
  }) async {
    final server = state.selectedServer;
    if (server == null) return (success: false, error: 'No server selected');

    final response = await _callWithAutoRefresh((token) => call(server, token));
    if (!response.success) {
      return (success: false, error: response.error ?? failure);
    }

    await refreshServerDetails();
    _onServerEvent?.call(server.id);
    return (success: true, error: null);
  }
}
