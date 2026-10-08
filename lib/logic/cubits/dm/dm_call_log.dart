part of 'dm_cubit.dart';

/// The open conversation's calls, kept beside its messages.
///
/// Read for exactly the stretch of history on screen — from the oldest loaded
/// message when there is more above it, from the beginning when there is not
/// — and read again whenever that stretch moves, a call changes, or another
/// conversation opens. The answer is metadata the server already holds; the
/// call itself was never anywhere it could read.
mixin _DmCallLogMixin on Cubit<DmState> {
  ServerCubit get _serverCubit;
  DmCallsApi get _calls;

  /// What the last read was for, so a state that moved nothing the log
  /// depends on — a keystroke's typing indicator, a reaction — asks nothing.
  String? _callLogFor;

  /// Called on every change, from [DmCubit.onChange].
  void _followCallLog(DmState next) {
    if (next.chatStatus != DmChatStatus.ready || next.openPeerId == null) {
      _callLogFor = null;
      return;
    }
    final key =
        '${next.openPeerId}|${next.messages.firstOrNull?.id}|'
        '${next.hasMoreHistory}|${next.hasNewerHistory}';
    if (key == _callLogFor) return;
    _callLogFor = key;
    unawaited(refreshCallLog());
  }

  Future<void> refreshCallLog() async {
    final peerId = state.openPeerId;
    final server = _serverCubit.state.selectedServer;
    if (peerId == null || server == null) return;
    final since = state.hasMoreHistory
        ? state.messages.firstOrNull?.sentAt
        : null;
    final response = await _calls.dmCallLog(
      server,
      peerId: peerId,
      since: since,
    );
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
