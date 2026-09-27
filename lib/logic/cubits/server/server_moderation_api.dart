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

  /// Open reports, or the closed ones kept for 90 days.
  Future<APIResponse> listReports({required bool open}) => _callWithAutoRefresh(
    (token) => _repository.listReports(
      _url,
      anonKey: _anonKey,
      bearerToken: token,
      open: open,
    ),
  );

  Future<APIResponse> resolveReport({
    required int reportId,
    required ReportOutcome outcome,
  }) => _callWithAutoRefresh(
    (token) => _repository.resolveReport(
      _url,
      anonKey: _anonKey,
      bearerToken: token,
      reportId: reportId,
      outcome: outcome.toJson(),
    ),
  );

  // ── Time-outs ─────────────────────────────────────────────

  /// Time [targetId] out for [duration]; [Duration.zero] lifts it.
  Future<APIResponse> timeOutMember({
    required String targetId,
    required Duration duration,
  }) => _callWithAutoRefresh(
    (token) => _repository.timeOutMember(
      _url,
      anonKey: _anonKey,
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
