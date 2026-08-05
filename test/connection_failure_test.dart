import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:rift/logic/services/connection_failure.dart';

lk.ConnectException _connect(
  String body, {
  int statusCode = 0,
  lk.ConnectionErrorReason reason = lk.ConnectionErrorReason.InternalError,
}) => lk.ConnectException(body, reason: reason, statusCode: statusCode);

void main() {
  group('ConnectionFailure.from', () {
    test('reads a 404 as the room having been closed, not as a refusal', () {
      // Rift's edge function creates the room when it mints a token, and
      // LiveKit reaps empty rooms — so a cached token can arrive at a room that
      // no longer exists. Retrying re-mints, which re-creates it.
      final failure = ConnectionFailure.from(
        _connect(
          'requested room does not exist',
          statusCode: 404,
          reason: lk.ConnectionErrorReason.NotAllowed,
        ),
      );

      expect(failure.title, contains('no room open'));
      expect(failure.canRetry, isTrue);
      // The 404 arrives as NotAllowed, so matching on `reason` alone would
      // file this under "permission denied" and tell the user the wrong thing.
      expect(failure.title, isNot(contains('refused')));
    });

    test('recognises the room-gone body even without a status code', () {
      final failure = ConnectionFailure.from(
        _connect('requested room does not exist'),
      );

      expect(failure.title, contains('no room open'));
    });

    test('reads 401 and 403 as the token being refused', () {
      for (final code in [401, 403]) {
        final failure = ConnectionFailure.from(
          _connect(
            'permission denied',
            statusCode: code,
            reason: lk.ConnectionErrorReason.NotAllowed,
          ),
        );

        expect(failure.title, contains('refused'), reason: 'status $code');
        expect(failure.canRetry, isTrue);
      }
    });

    test(
      'reads a socket that never opened as the server being unreachable',
      () {
        final failure = ConnectionFailure.from(
          const SocketException('Connection refused'),
        );

        expect(failure.message, contains('offline'));
        expect(failure.canRetry, isTrue);
      },
    );

    test('reads the SDK 503 as unreachable too', () {
      final failure = ConnectionFailure.from(
        _connect('no internet connection', statusCode: 503),
      );

      expect(failure.message, contains('offline'));
    });

    test('separates a blocked media path from an unreachable server', () {
      final failure = ConnectionFailure.from(lk.MediaConnectException());

      // The signalling connection succeeded here; saying "offline" would send
      // the user to check entirely the wrong thing.
      expect(failure.message, isNot(contains('offline')));
      expect(failure.message.toLowerCase(), contains('firewall'));
    });

    test('reads a timeout as slow rather than absent', () {
      final failure = ConnectionFailure.from(
        _connect(
          'Timed out waiting for SignalJoinResponseEvent',
          reason: lk.ConnectionErrorReason.Timeout,
        ),
      );

      expect(failure.title, contains('did not respond'));
    });

    test('reads a track failure as a device problem', () {
      final failure = ConnectionFailure.from(lk.TrackCreateException());

      expect(failure.title, contains('Microphone'));
    });

    test('keeps the original text as the detail line', () {
      final failure = ConnectionFailure.from(
        _connect('requested room does not exist', statusCode: 404),
      );

      // The message above it is an interpretation; a bug report needs the
      // untranslated cause.
      expect(failure.detail, 'requested room does not exist');
    });

    test('strips the SDK class-name prefix from the detail', () {
      final failure = ConnectionFailure.from(_connect('some raw body'));

      expect(failure.detail, 'some raw body');
      expect(failure.detail, isNot(contains('LiveKit Exception')));
    });

    test('falls back without losing the error for anything unrecognised', () {
      final failure = ConnectionFailure.from(StateError('nope'));

      expect(failure.title, isNotEmpty);
      expect(failure.detail, contains('nope'));
      expect(failure.canRetry, isTrue);
    });
  });

  group('non-connection failures', () {
    test('configuration problems are not offered a retry', () {
      expect(const ConnectionFailure.noServer().canRetry, isFalse);
      expect(const ConnectionFailure.noLiveKitUrl().canRetry, isFalse);
    });

    test('a failed token request is, since that call creates the room', () {
      const failure = ConnectionFailure.tokenRequest('edge function 500');

      expect(failure.canRetry, isTrue);
      expect(failure.detail, 'edge function 500');
    });
  });
}
