import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/api_response.dart';
import '../../../data/classes/chat_message.dart';
import '../../../data/classes/member_report.dart';
import '../../../data/classes/server.dart';
import '../../../data/enums/report_outcome.dart';
import '../../../data/enums/server_permission.dart';
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
class ReportsCubit extends Cubit<ReportsState> {
  final ServerCubit _serverCubit;
  final ReportedMessageOpener _opener;

  StreamSubscription<ServerState>? _serverSub;
  final List<RealtimeLease> _leases = [];
  String? _watchingServerId;

  late final CoalescedRefresh<void> _refresh = CoalescedRefresh(_readOpen);

  ReportsCubit({
    required ServerCubit serverCubit,
    required VaultCubit vaultCubit,
  }) : _serverCubit = serverCubit,
       _opener = ReportedMessageOpener(
         serverCubit: serverCubit,
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
    final server = _serverCubit.state.selectedServer;
    final canReview = _mayReview(server);
    final serverId = canReview ? server!.id : null;
    if (serverId == _watchingServerId) return;

    unawaited(_stopWatching());
    _opener.clear();
    emit(ReportsState(canReview: canReview));
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
    final response = await _serverCubit.listReports(open: open);
    if (!response.success) return null;
    final entries = <ReportEntry>[];
    for (final row in (response.data as List).cast<Map<String, dynamic>>()) {
      final report = MemberReport.fromJson(row);
      if (report.message == null) {
        entries.add(ReportEntry(report: report));
        continue;
      }
      final opened = await _opener.open(report);
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
    final deleted = await _serverCubit.deleteChatMessage(
      channelId: reported.channelId,
      messageId: reported.id,
    );
    if (!deleted.success) return deleted;
    unawaited(
      AttachmentCleanup.forMessage(
        entry.message,
        delete: _serverCubit.deleteAttachments,
      ),
    );
    return _record(entry, ReportOutcome.deleted);
  }

  Future<APIResponse> timeOut(ReportEntry entry, Duration duration) async {
    final target = entry.report.targetId;
    if (target == null) return APIResponse.error('Nobody to time out');
    final done = await _serverCubit.timeOutMember(
      targetId: target,
      duration: duration,
    );
    if (!done.success) return done;
    return _record(entry, ReportOutcome.timedOut);
  }

  Future<APIResponse> ban(ReportEntry entry) async {
    final target = entry.report.targetId;
    if (target == null) return APIResponse.error('Nobody to ban');
    final done = await _serverCubit.moderateUser(
      userId: target,
      isBanned: true,
    );
    if (!done.success) return done;
    return _record(entry, ReportOutcome.banned);
  }

  /// Kick them: out now, back through a new invite. Closes every open
  /// report about them, as a ban does.
  Future<APIResponse> kick(ReportEntry entry) async {
    final target = entry.report.targetId;
    if (target == null) return APIResponse.error('Nobody to kick');
    final done = await _serverCubit.kickMember(userId: target);
    if (!done.success) return done;
    return _record(entry, ReportOutcome.kicked);
  }

  Future<APIResponse> _record(ReportEntry entry, ReportOutcome outcome) async {
    final response = await _serverCubit.resolveReport(
      reportId: entry.report.id,
      outcome: outcome,
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
