part of 'server_cubit.dart';

/// Reports, time-outs, blocks and who may start a DM, on the selected server.
///
/// Pass-throughs, like the pins: the reports page and the DM cubit hold the
/// state. The one exception is [setDmPolicy], which is our own row and is
/// reflected locally at once, the way a profile change is.
mixin _ServerModerationApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  String get _anonKey;
  String get _userId;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );
  void _replaceServer(Server server);
  Future<APIResponse> _callFor(
    Server server,
    Future<APIResponse> Function(String token) call,
  );
  Server? _target(String? serverId);
  String _noTarget(String? serverId);

  String get _url => state.selectedServer!.supabaseUrl;

  // ── Reports ───────────────────────────────────────────────

  Future<APIResponse> reportMessage({
    required int messageId,
    required MemberReportReason reason,
    String? note,
  }) => _callWithAutoRefresh(
    (token) => _repository.reportMessage(
      _url,
      anonKey: _anonKey,
      bearerToken: token,
      messageId: messageId,
      reason: reason.toJson(),
      note: note,
    ),
  );

  Future<APIResponse> reportMember({
    required String targetId,
    required MemberReportReason reason,
    String? note,
  }) => _callWithAutoRefresh(
    (token) => _repository.reportMember(
      _url,
      anonKey: _anonKey,
      bearerToken: token,
      targetId: targetId,
      reason: reason.toJson(),
      note: note,
    ),
  );

  /// Open reports, or the closed ones kept for 90 days, on [serverId] or the
  /// selected server — the reports page opens for any server on the rail.
  Future<APIResponse> listReports({required bool open, String? serverId}) =>
      _onServer(
        serverId,
        (server, token) => _repository.listReports(
          server.supabaseUrl,
          anonKey: server.supabaseKey ?? '',
          bearerToken: token,
          open: open,
        ),
      );

  Future<APIResponse> resolveReport({
    required int reportId,
    required ReportOutcome outcome,
    String? serverId,
  }) => _onServer(
    serverId,
    (server, token) => _repository.resolveReport(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      reportId: reportId,
      outcome: outcome.toJson(),
    ),
  );

  /// [call] against [serverId], or the selected server.
  Future<APIResponse> _onServer(
    String? serverId,
    Future<APIResponse> Function(Server server, String token) call,
  ) async {
    final server = _target(serverId);
    if (server == null) return APIResponse.error(_noTarget(serverId));
    return _callFor(server, (token) => call(server, token));
  }

  // ── Time-outs ─────────────────────────────────────────────

  /// Time [targetId] out for [duration]; [Duration.zero] lifts it.
  Future<APIResponse> timeOutMember({
    required String targetId,
    required Duration duration,
    String? serverId,
  }) => _onServer(
    serverId,
    (server, token) => _repository.timeOutMember(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      targetId: targetId,
      minutes: duration.inMinutes,
    ),
  );

  // ── Blocks ────────────────────────────────────────────────

  Future<APIResponse> listBlocks() => _callWithAutoRefresh(
    (token) =>
        _repository.listBlocks(_url, anonKey: _anonKey, bearerToken: token),
  );

  Future<APIResponse> setBlocked({
    required String peerId,
    required bool blocked,
  }) => _callWithAutoRefresh(
    (token) => _repository.setBlocked(
      _url,
      anonKey: _anonKey,
      bearerToken: token,
      userId: _userId,
      peerId: peerId,
      blocked: blocked,
    ),
  );

  // ── Who may start a DM ────────────────────────────────────

  Future<APIResponse> setDmPolicy(DmPolicy policy) async {
    final server = state.selectedServer;
    final user = server?.user;
    if (server == null || user == null) {
      return APIResponse.error('No server selected');
    }
    final response = await _callWithAutoRefresh(
      (token) => _repository.setDmPolicy(
        server.supabaseUrl,
        anonKey: _anonKey,
        bearerToken: token,
        userId: user.id,
        policy: policy.toJson(),
      ),
    );
    if (response.success) {
      _replaceServer(server.copyWith(user: user.copyWith(dmPolicy: policy)));
    }
    return response;
  }

  Future<APIResponse> dmLinkState({required String peerId}) =>
      _callWithAutoRefresh(
        (token) => _repository.dmLinkState(
          _url,
          anonKey: _anonKey,
          bearerToken: token,
          peerId: peerId,
        ),
      );

  Future<APIResponse> dmRequests() => _callWithAutoRefresh(
    (token) =>
        _repository.dmRequests(_url, anonKey: _anonKey, bearerToken: token),
  );

  Future<APIResponse> answerDmRequest({
    required String peerId,
    required bool accept,
  }) => _callWithAutoRefresh(
    (token) => _repository.answerDmRequest(
      _url,
      anonKey: _anonKey,
      bearerToken: token,
      peerId: peerId,
      accept: accept,
    ),
  );
}
