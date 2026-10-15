part of 'livekit_cubit.dart';

/// Watching somebody's stream from the sidebar, which may mean joining their
/// call first.
///
/// The press comes before there is anything to watch: the call is still
/// connecting, and the sharer's connection arrives with the rest of the room a
/// moment after. So the wish is held, and every sync of the room checks it,
/// until the stream turns up or [_waitFor] runs out.
mixin _WatchRequestMixin on Cubit<LiveKitState> {
  Future<void> subscribeToScreenshare(String identity);

  /// Whose stream to open, in which call, and until when to keep looking.
  ({String userId, String channelId, DateTime until})? _wanted;

  /// Long enough for a join on a slow server; short enough that a stream that
  /// ended meanwhile does not spring open on some later visit.
  static const _waitFor = Duration(seconds: 20);

  /// Open [userId]'s stream in [channelId] once this client is in that call
  /// and the stream is there: watch it, and ask the stage to show it full
  /// size ([LiveKitState.streamToOpen]).
  void watchStreamOf(String userId, {required String channelId}) {
    _wanted = (
      userId: userId,
      channelId: channelId,
      until: DateTime.now().add(_waitFor),
    );
    _openWanted();
  }

  /// The stage has opened [LiveKitState.streamToOpen].
  void streamOpened() {
    if (state.streamToOpen != null) {
      emit(state.copyWith(clearStreamToOpen: true));
    }
  }

  void _openWanted() {
    final wanted = _wanted;
    if (wanted == null) return;
    if (DateTime.now().isAfter(wanted.until)) {
      _wanted = null;
      return;
    }
    if (state.connectionState != LiveKitConnectionState.connected ||
        state.currentChannelId != wanted.channelId) {
      return;
    }
    final identity = screenOf(
      state.participants,
      wanted.userId,
      identityOf: (p) => p.identity,
      publishesScreenshare: (p) => p.videoTrackPublications.any(
        (pub) => pub.source == TrackSource.screenShareVideo,
      ),
    );
    if (identity == null) return;
    _wanted = null;
    // Watching first: it records the stream as watched before it awaits
    // anything, and the stage that opens it checks for exactly that.
    final watching = state.subscribedScreenshares.contains(identity)
        ? null
        : subscribeToScreenshare(identity);
    emit(state.copyWith(streamToOpen: identity));
    if (watching != null) unawaited(watching);
  }
}
