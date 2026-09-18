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

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  /// Implemented by [_ServerApiMixin].
  Future<({bool success, String? error})> refreshServerDetails();

  /// Create a new channel in the selected server.
  ///
  /// [memberIds] is only read when [isPrivate], and never has to include the
  /// creator: `create_channel` seats them itself (`007_channels.sql`).
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

    // Our own list, to include the channel we just made. Everybody else
    // hears it from the database — `channels_announce` (migration 017) fires
    // on the row, so it reaches members who were offline when we rang and
    // members on a server nobody rang. The doorbell used to be sent here too
    // and only ever arrived as a second identical answer.
    await refreshServerDetails();
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

  /// Runs a channel mutation, then brings everyone's sidebar in line: our own
  /// list directly, and other members' through `channels_announce` on the
  /// row itself — which is immediate, and reaches people no ping could.
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
    return (success: true, error: null);
  }
}
