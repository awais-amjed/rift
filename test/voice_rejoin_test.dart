import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:rift/logic/services/voice_rejoin.dart';

void main() {
  group('rejoinsAfter', () {
    test('joins again when the connection gave out', () {
      for (final reason in [
        lk.DisconnectReason.reconnectAttemptsExceeded,
        lk.DisconnectReason.signalingConnectionFailure,
        lk.DisconnectReason.serverShutdown,
      ]) {
        expect(VoiceRejoin.rejoinsAfter(reason), isTrue, reason: reason.name);
      }
    });

    test('does not undo somebody\'s decision to end the call', () {
      for (final reason in [
        lk.DisconnectReason.participantRemoved,
        lk.DisconnectReason.roomDeleted,
        lk.DisconnectReason.duplicateIdentity,
        lk.DisconnectReason.clientInitiated,
        lk.DisconnectReason.joinFailure,
        lk.DisconnectReason.stateMismatch,
        lk.DisconnectReason.disconnected,
        lk.DisconnectReason.unknown,
      ]) {
        expect(VoiceRejoin.rejoinsAfter(reason), isFalse, reason: reason.name);
      }
      expect(VoiceRejoin.rejoinsAfter(null), isFalse);
    });
  });
}
