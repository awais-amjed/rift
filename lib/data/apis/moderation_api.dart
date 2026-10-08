import '../classes/api_response.dart';
import '../classes/server.dart';
import '../enums/dm_policy.dart';
import '../enums/member_report_reason.dart';
import '../enums/report_outcome.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';

/// Acting on a person: server mutes, bans and kicks, time-outs, reports, and
/// the DM gate — blocks, who may start a DM, and the requests it holds back.
///
/// Pass-throughs: the reports page, the members page and the DM cubit hold
/// the state. The one exception is [setDmPolicy], which is our own row, and
/// re-reads the server so the list holds the new setting when it answers.
///
/// The calls a page can make about a server the person is not looking at take
/// a `serverId`; the rest act on the selected server. Holds nothing, so a
/// widget builds one from the session.
class ModerationApi {
  final SessionRepository _session;

  ModerationApi({required SessionRepository session}) : _session = session;

  ServerRepository get _repository => _session.repository;

  /// [call] against [serverId], or the selected server.
  Future<APIResponse> _onServer(
    String? serverId,
    Future<APIResponse> Function(Server server, String token) call,
  ) async {
    final server = _session.target(serverId);
    if (server == null) return APIResponse.error(_session.noTarget(serverId));
    return _session.callFor(server, (token) => call(server, token));
  }

  // ── Server-wide mutes, bans and kicks ─────────────────────

  /// Persistently mutes/deafens/bans a user server-wide on [serverId], or on
  /// the selected server (requires channel manager or server admin).
  ///
  /// Omitted flags are left as they are — the endpoint reads the row back and
  /// reports the whole state, so a caller changing one thing never has to know
  /// the others.
  ///
  /// A ban is the persistent end of moderation: it removes them from every
  /// live call immediately and RLS refuses them everything afterwards. Setting
  /// [isBanned] false lets them back in; nothing else about them changed while
  /// they were out.
  Future<APIResponse> moderateUser({
    required String userId,
    bool? isMuted,
    bool? isDeafened,
    bool? isBanned,
    String? serverId,
  }) => _onServer(
    serverId,
    (server, token) => _repository.moderateUser(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      userId: userId,
      isMuted: isMuted,
      isDeafened: isDeafened,
      isBanned: isBanned,
    ),
  );

  /// Removes somebody until they come back through a new invite.
  ///
  /// A ban the next invite lifts (`kick_member`): out of every call now, and
  /// back as a newcomer — their roles and private-channel seats are gone,
  /// their name and messages are not. `KICK_MEMBERS`, checked by the server.
  Future<APIResponse> kickMember({required String userId, String? serverId}) =>
      _onServer(
        serverId,
        (server, token) => _repository.moderateUser(
          server.supabaseUrl,
          anonKey: server.supabaseKey ?? '',
          bearerToken: token,
          userId: userId,
          kick: true,
        ),
      );

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

  // ── Reports ───────────────────────────────────────────────

  Future<APIResponse> reportMessage({
    required int messageId,
    required MemberReportReason reason,
    String? note,
  }) => _onServer(
    null,
    (server, token) => _repository.reportMessage(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
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
  }) => _onServer(
    null,
    (server, token) => _repository.reportMember(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
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

  // ── Blocks ────────────────────────────────────────────────

  Future<APIResponse> listBlocks() => _onServer(
    null,
    (server, token) => _repository.listBlocks(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
    ),
  );

  Future<APIResponse> setBlocked({
    required String peerId,
    required bool blocked,
  }) => _onServer(
    null,
    (server, token) => _repository.setBlocked(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      userId: server.user?.id ?? '',
      peerId: peerId,
      blocked: blocked,
    ),
  );

  // ── Who may start a DM ────────────────────────────────────

  /// Our own row, so the server is read again once it is saved: the setting
  /// lives on the server list's copy of us, which the dialog draws from.
  Future<APIResponse> setDmPolicy(DmPolicy policy) async {
    final server = _session.selectedServer;
    final user = server?.user;
    if (server == null || user == null) {
      return APIResponse.error('No server selected');
    }
    final response = await _session.callFor(
      server,
      (token) => _repository.setDmPolicy(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        userId: user.id,
        policy: policy.toJson(),
      ),
    );
    if (response.success) await _session.refreshDetails(server);
    return response;
  }

  Future<APIResponse> dmLinkState({required String peerId}) => _onServer(
    null,
    (server, token) => _repository.dmLinkState(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      peerId: peerId,
    ),
  );

  Future<APIResponse> dmRequests() => _onServer(
    null,
    (server, token) => _repository.dmRequests(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
    ),
  );

  Future<APIResponse> answerDmRequest({
    required String peerId,
    required bool accept,
  }) => _onServer(
    null,
    (server, token) => _repository.answerDmRequest(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      peerId: peerId,
      accept: accept,
    ),
  );
}
