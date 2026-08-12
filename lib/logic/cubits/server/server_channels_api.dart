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
  String get _serverId;

  /// Ping the `server_events` doorbell after a structural change so other
  /// members refresh in realtime.
  void Function()? get _onServerEvent;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  /// Implemented by [_ServerApiMixin].
  Future<({bool success, String? error})> refreshServerDetails();

  /// Create a new channel in the selected server.
  Future<({bool success, String? error})> createChannel({
    required String name,
    required String channelType,
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final response = await _callWithAutoRefresh(
      (token) => _repository.createChannel(
        server.supabaseUrl,
        anonKey: _anonKey,
        serverId: _serverId,
        bearerToken: token,
        name: name,
        channelType: channelType,
      ),
    );

    if (!response.success) {
      return (
        success: false,
        error: response.error ?? 'Failed to create channel',
      );
    }

    // Refresh our own channel list to include the newly created one, and ping
    // the server_events doorbell so other members refresh in realtime.
    await refreshServerDetails();
    _onServerEvent?.call();
    return (success: true, error: null);
  }

  /// Change a channel's name and/or its daily quota (channel manager only).
  ///
  /// [dailyQuota] omitted leaves the quota alone; [clearDailyQuota] puts the
  /// channel back to inheriting the server's default.
  Future<({bool success, String? error})> updateChannel({
    required String channelId,
    String? name,
    int? dailyQuota,
    bool clearDailyQuota = false,
  }) => _changeChannel(
    (server, token) => _repository.updateChannel(
      server.supabaseUrl,
      channelId,
      anonKey: _anonKey,
      bearerToken: token,
      name: name,
      dailyQuota: dailyQuota,
      clearDailyQuota: clearDailyQuota,
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
    _onServerEvent?.call();
    return (success: true, error: null);
  }
}
