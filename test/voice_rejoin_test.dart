import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:rift/logic/services/voice_rejoin.dart';

lk.ConnectException _connect(String body, {int statusCode = 0}) =>
    lk.ConnectException(
      body,
      reason: lk.ConnectionErrorReason.NotAllowed,
      statusCode: statusCode,
    );

void main() {
  group('refusedCachedToken', () {
    test('a token signed with replaced credentials is worth minting again', () {
      // What LiveKit answered, verbatim apart from the key, after the voice
      // credentials were replaced under a running call.
      expect(
        VoiceRejoin.refusedCachedToken(
          _connect('invalid API key: APIold', statusCode: 401),
        ),
        isTrue,
      );
      expect(
        VoiceRejoin.refusedCachedToken(
          _connect('permission denied', statusCode: 403),
        ),
        isTrue,
      );
    });

    test('a room closed while the token was cached is worth minting again', () {
      expect(
        VoiceRejoin.refusedCachedToken(
          _connect('requested room does not exist', statusCode: 404),
        ),
        isTrue,
      );
      expect(
        VoiceRejoin.refusedCachedToken(
          _connect('requested room does not exist'),
        ),
        isTrue,
      );
    });

    test('a server that is not answering is not the token\'s fault', () {
      // A new token would fail identically, and retrying silently would only
      // delay the screen that says what is actually wrong.
      expect(
        VoiceRejoin.refusedCachedToken(
          _connect('no internet connection', statusCode: 503),
        ),
        isFalse,
      );
      expect(
        VoiceRejoin.refusedCachedToken(const SocketException('refused')),
        isFalse,
      );
      expect(
        VoiceRejoin.refusedCachedToken(lk.MediaConnectException()),
        isFalse,
      );
    });
  });

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
