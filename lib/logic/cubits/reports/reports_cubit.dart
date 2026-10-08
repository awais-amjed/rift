import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/apis/moderation_api.dart';
import '../../../data/classes/api_response.dart';
import '../../../data/classes/chat_message.dart';
import '../../../data/classes/member_report.dart';
import '../../../data/classes/server.dart';
import '../../../data/enums/report_outcome.dart';
import '../../../data/enums/server_permission.dart';
import '../../../data/repositories/session_repository.dart';
import '../../services/attachment_cleanup.dart';
import '../../services/coalesced_refresh.dart';
import '../../services/reported_message_opener.dart';
import '../../services/server_realtime.dart';
import '../../services/server_topics.dart';
import '../server/server_cubit.dart';
import '../vault/vault_cubit.dart';

part 'reports_state.dart';

/// What members of the selected server have reported, for whoever may review
/// it — and doing something about each one.
///
/// Alive for as long as the app is, like the notifications cubit: the badge
/// on the Reports page has to move when a report arrives, not when somebody
/// happens to open the page. For a member who cannot review, it holds nothing
/// and listens to nothing.
///
/// An action is two steps, in this order: do it (delete, time out, kick, ban)
/// through the path that action always takes, then record it with
/// `resolve_report`, which checks it happened. Recording first would log a
/// ban the server then refused.
///
/// Given a [serverId] it is that one server's instead, for Manage server opened
/// on a server the person is not looking at; that page owns it and closes it.
class ReportsCubit extends Cubit<ReportsState> {
  final ServerCubit _serverCubit;
  final ModerationApi _moderation;
  final ReportedMessageOpener _opener;

  /// The one server this watches, or null to follow the selection.
  final String? _fixedServerId;

  StreamSubscription<ServerState>? _serverSub;
  final List<RealtimeLease> _leases = [];
  String? _watchingServerId;

  late final CoalescedRefresh<void> _refresh = CoalescedRefresh(_readOpen);

  ReportsCubit({
    required ServerCubit serverCubit,
    required SessionRepository session,
    required VaultCubit vaultCubit,
    String? serverId,
  }) : _serverCubit = serverCubit,
       _moderation = ModerationApi(session: session),
       _fixedServerId = serverId,
       _opener = ReportedMessageOpener(
         session: session,
         vaultCubit: vaultCubit,
       ),
       super(const ReportsState()) {
    _serverSub = serverCubit.stream.listen((_) => _onServerChanged());
    _onServerChanged();
  }

  static bool _mayReview(Server? server) =>
      server?.user?.permissions.can(ServerPermission.reviewReports) ?? false;

  /// A server switch, or a role change on this one, decides whether there is
  /// anything to watch.
  void _onServerChanged() {
    final fixed = _fixedServerId;
    final server = fixed == null
        ? _serverCubit.state.selectedServer
        : _serverCubit.state.serverById(fixed);
    final canReview = _mayReview(server);
    final serverId = canReview ? server!.id : null;
    if (serverId == _watchingServerId) return;

    unawaited(_stopWatching());
    _opener.clear();
    emit(ReportsState(canReview: canReview, serverId: serverId));
    if (serverId == null) return;

    _watchingServerId = serverId;
    final user = server!.user!;
    // Both topics: a reviewer is rung on their own, unless `@everyone`
    // reviews, when the server's topic is the honest address.
    for (final topic in [
      ServerTopics.user(user.id),
      ServerTopics.server(serverId),
    ]) {
      final lease = _serverCubit.realtime.join(server, topic)
        ?..onBroadcast(ServerEvent.reports, (_) => unawaited(refresh()));
      if (lease != null) _leases.add(lease);
    }
    unawaited(refresh());
  }

  Future<void> _stopWatching() async {
    _watchingServerId = null;
    final leases = [..._leases];
    _leases.clear();
    for (final lease in leases) {
      await lease.release();
    }
  }

  /// Re-read the open reports. Several rings at once are one read.
  Future<void> refresh() => _refresh();

  Future<void> _readOpen() async {
    final serverId = _watchingServerId;
    if (serverId == null) return;
    emit(state.copyWith(loading: true, clearError: true));
    final entries = await _read(open: true);
    if (isClosed || _watchingServerId != serverId) return;
    if (entries == null) {
      emit(state.copyWith(loading: false, error: 'Could not load reports.'));
      return;
    }
    emit(state.copyWith(open: entries, loading: false));
    if (state.closedLoaded) unawaited(loadClosed());
  }

  /// The closed reports the server still keeps (90 days).
  Future<void> loadClosed() async {
    final serverId = _watchingServerId;
    if (serverId == null) return;
    final entries = await _read(open: false);
    if (isClosed || _watchingServerId != serverId || entries == null) return;
    emit(state.copyWith(closed: entries, closedLoaded: true));
  }

  Future<List<ReportEntry>?> _read({required bool open}) async {
    final response = await _moderation.listReports(
      open: open,
      serverId: _watchingServerId,
    );
    if (!response.success) return null;
    final entries = <ReportEntry>[];
    for (final row in (response.data as List).cast<Map<String, dynamic>>()) {
      final report = MemberReport.fromJson(row);
      if (report.message == null) {
        entries.add(ReportEntry(report: report));
        continue;
      }
      final opened = await _opener.open(report, serverId: _watchingServerId);
      entries.add(
        ReportEntry(
          report: report,
          content: opened.content,
          message: opened.message,
        ),
      );
    }
    return entries;
  }

  // ── Acting on one ─────────────────────────────────────────

  Future<APIResponse> dismiss(ReportEntry entry) =>
      _record(entry, ReportOutcome.dismissed);

  /// Delete the reported message, with its attachments when this device
  /// could open it to know which they are. A message its author already
  /// deleted is already the outcome wanted.
  Future<APIResponse> deleteMessage(ReportEntry entry) async {
    final reported = entry.report.message;
    if (reported == null) return APIResponse.error('Not a message report');
    final serverId = _watchingServerId;
    final deleted = await _serverCubit.deleteChatMessage(
      channelId: reported.channelId,
      messageId: reported.id,
      serverId: serverId,
    );
    if (!deleted.success) return deleted;
    unawaited(
      AttachmentCleanup.forMessage(
        entry.message,
        delete: (paths) =>
            _serverCubit.deleteAttachments(paths, serverId: serverId),
      ),
    );
    return _record(entry, ReportOutcome.deleted);
  }

  Future<APIResponse> timeOut(ReportEntry entry, Duration duration) async {
    final target = entry.report.targetId;
    if (target == null) return APIResponse.error('Nobody to time out');
    final done = await _moderation.timeOutMember(
      targetId: target,
      duration: duration,
      serverId: _watchingServerId,
    );
    if (!done.success) return done;
    return _record(entry, ReportOutcome.timedOut);
  }

  Future<APIResponse> ban(ReportEntry entry) async {
    final target = entry.report.targetId;
    if (target == null) return APIResponse.error('Nobody to ban');
    final done = await _moderation.moderateUser(
      userId: target,
      isBanned: true,
      serverId: _watchingServerId,
    );
    if (!done.success) return done;
    return _record(entry, ReportOutcome.banned);
  }

  /// Kick them: out now, back through a new invite. Closes every open
  /// report about them, as a ban does.
  Future<APIResponse> kick(ReportEntry entry) async {
    final target = entry.report.targetId;
    if (target == null) return APIResponse.error('Nobody to kick');
    final done = await _moderation.kickMember(
      userId: target,
      serverId: _watchingServerId,
    );
    if (!done.success) return done;
    return _record(entry, ReportOutcome.kicked);
  }

  Future<APIResponse> _record(ReportEntry entry, ReportOutcome outcome) async {
    final response = await _moderation.resolveReport(
      reportId: entry.report.id,
      outcome: outcome,
      serverId: _watchingServerId,
    );
    if (!isClosed) unawaited(refresh());
    return response;
  }

  @override
  Future<void> close() async {
    await _serverSub?.cancel();
    await _stopWatching();
    return super.close();
  }
}
