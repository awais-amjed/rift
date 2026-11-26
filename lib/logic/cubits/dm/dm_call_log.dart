part of 'dm_cubit.dart';

/// The open conversation's calls, kept beside its messages.
///
/// Read for exactly the stretch of history on screen — from the oldest loaded
/// message when there is more above it, from the beginning when there is not
/// — and read again whenever that stretch moves, a call changes, or another
/// conversation opens. The answer is metadata the server already holds; the
/// call itself was never anywhere it could read.
mixin _DmCallLogMixin on Cubit<DmState>, _DmHistoryMixin {
  DmCallsApi get _calls;

  /// What the last read was for, so a state that moved nothing the log
  /// depends on — a keystroke's typing indicator, a reaction — asks nothing.
  String? _callLogFor;

  static String _callLogKey(DmState s) =>
      '${s.openPeerId}|${s.messages.firstOrNull?.id}|'
      '${s.hasMoreHistory}|${s.hasNewerHistory}';

  /// Called on every change, from [DmCubit.onChange].
  void _followCallLog(DmState next) {
    if (next.chatStatus != DmChatStatus.ready || next.openPeerId == null) {
      _callLogFor = null;
      return;
    }
    final key = _callLogKey(next);
    if (key == _callLogFor) return;
    _callLogFor = key;
    unawaited(refreshCallLog());
  }

  /// The calls `dm_open` read beside the page just drawn, from the row
  /// [sinceId] names (null: from the start). Kept, and not read again when
  /// the conversation turns ready, only when that row is the oldest message
  /// drawn: a row dropped as forged moves the stretch, and then the log is
  /// read for the one on screen as usual.
  @override
  void _takeOpenedCalls(String peerId, List<dynamic>? calls, String? sinceId) {
    if (calls == null || isClosed || state.openPeerId != peerId) return;
    if (state.hasNewerHistory) return;
    final oldest = state.messages.firstOrNull?.id;
    final drawnFrom = state.hasMoreHistory ? oldest : null;
    if (drawnFrom != sinceId) return;
    emit(state.copyWith(calls: DmCall.listFrom(calls)));
    // After the emit, which (still loading) cleared it.
    _callLogFor = _callLogKey(state);
  }

  Future<void> refreshCallLog() async {
    final peerId = state.openPeerId;
    final server = _server;
    if (peerId == null || server == null) return;
    final since = state.hasMoreHistory
        ? state.messages.firstOrNull?.sentAt
        : null;
    final response = await _calls.dmCallLog(peerId: peerId, since: since);
    if (!response.success || isClosed || state.openPeerId != peerId) return;
    var calls = DmCall.listFrom(response.data);
    // A window into the past has later history that is not loaded, and a
    // call from after it would sit under the last message as if it followed.
    final last = state.messages.lastOrNull?.sentAt;
    if (state.hasNewerHistory && last != null) {
      calls = [
        for (final call in calls)
          if (!call.startedAt.isAfter(last)) call,
      ];
    }
    emit(state.copyWith(calls: calls));
  }
}
