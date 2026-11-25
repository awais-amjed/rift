import 'package:livekit_client/livekit_client.dart' as lk;

/// When a call joins again by itself, rather than handing the user an error.
///
/// Found by replacing the voice server's credentials under a live call
/// between two desktop clients: every token minted before that is signed with
/// a key LiveKit no longer knows, so a call in progress loses its connection
/// and cannot get it back with the token it holds — the SDK retries with that
/// token for about 45 seconds and then gives up. Both dropped out of the call
/// without a word. A rejoin mints a new token, as every join does, and gets
/// straight back in.
abstract final class VoiceRejoin {
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
