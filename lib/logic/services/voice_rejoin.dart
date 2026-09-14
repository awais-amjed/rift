import 'package:livekit_client/livekit_client.dart' as lk;

/// When a call joins again by itself, rather than handing the user an error.
///
/// Both cases come from the same event: the voice server's credentials being
/// replaced from the console. Every token minted before that is signed with a
/// key LiveKit no longer knows. A call in progress loses its connection and
/// cannot get it back with the token it holds — the SDK retries with that token
/// for about 45 seconds and then gives up — and a rejoin that reaches for the
/// cached token is refused outright.
///
/// Found by replacing the credentials under a live call between two desktop
/// clients: both dropped out of the call without a word, and the first rejoin
/// on each failed with "invalid API key".
abstract final class VoiceRejoin {
  /// Whether [error], thrown while joining with a *cached* token, means that
  /// token is no good and a freshly minted one could get in.
  ///
  /// 401 and 403 are LiveKit refusing the token itself. 404 is the room having
  /// been closed while the token sat in the cache, and minting a new token is
  /// what opens it again. Anything else — nothing answering, a timeout, media
  /// blocked — would fail the same way with a new token, so it is left to the
  /// error screen.
  static bool refusedCachedToken(Object error) {
    if (error is! lk.ConnectException) return false;
    return const {401, 403, 404}.contains(error.statusCode) ||
        error.message.toLowerCase().contains('does not exist');
  }

  /// Whether a call that dropped for [reason] should be joined again.
  ///
  /// Only the reasons where the connection gave out, not the ones where
  /// somebody ended the call. Being removed, the room being deleted, or the
  /// same account joining from somewhere else are each a decision, and joining
  /// straight back in would undo it.
  static bool rejoinsAfter(lk.DisconnectReason? reason) => switch (reason) {
    lk.DisconnectReason.reconnectAttemptsExceeded ||
    lk.DisconnectReason.signalingConnectionFailure ||
    lk.DisconnectReason.serverShutdown => true,
    _ => false,
  };
}
