import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/enums/error_code.dart';
import 'package:rift/logic/services/chat_failure.dart';

void main() {
  group('ChatFailure.fromResponse', () {
    test('reads an unreachable server as being offline', () {
      final failure = ChatFailure.fromResponse(
        APIResponse.error(
          "Can't reach this server. It may be offline, or check your "
          'connection.',
          errorCode: ErrorCode.serverUnreachable,
        ),
      );

      expect(failure.title, contains('Cannot reach this server'));
      expect(failure.message, contains('offline'));
      expect(failure.offline, isTrue);
      // The channel key is a red herring here — nothing is wrong with the
      // encryption, the server simply did not answer.
      expect(failure.message, isNot(contains('key')));
    });

    test('passes the repository wording through rather than rewriting it', () {
      // The repository distinguishes a refused socket from a call that timed
      // out, and only its message carries that; the error code does not.
      final failure = ChatFailure.fromResponse(
        APIResponse.error(
          "This server isn't responding — it may be offline. Try again later.",
          errorCode: ErrorCode.serverUnreachable,
        ),
      );

      expect(failure.message, startsWith("This server isn't responding"));
      expect(failure.offline, isTrue);
    });

    test('reads a refusal as an access problem, not an outage', () {
      final failure = ChatFailure.fromResponse(
        APIResponse.error('nope', errorCode: ErrorCode.permissionDenied),
      );

      expect(failure.title, contains('No access'));
      expect(failure.offline, isFalse);
    });

    test('reads a missing channel as the channel being gone', () {
      final failure = ChatFailure.fromResponse(
        APIResponse.error('nope', errorCode: ErrorCode.channelNotFound),
      );

      expect(failure.title, contains('gone'));
      expect(failure.offline, isFalse);
    });

    test('keeps the server\'s own message for anything unrecognised', () {
      final failure = ChatFailure.fromResponse(
        APIResponse.error('keyring is on fire', errorCode: ErrorCode.dbError),
      );

      expect(failure.message, 'keyring is on fire');
      expect(failure.offline, isFalse);
    });

    test('still says something when the failure carries no message', () {
      final failure = ChatFailure.fromResponse(APIResponse(success: false));

      expect(failure.title, isNotEmpty);
      expect(failure.message, isNotEmpty);
    });
  });

  group('the failures that never reach the server', () {
    test('none of them claim the server is offline', () {
      const failures = [
        ChatFailure.unknown(),
        ChatFailure.noServer(),
        ChatFailure.vaultLocked(),
        ChatFailure.noKeyedMembers(),
        ChatFailure.keyringConflict(),
      ];

      for (final failure in failures) {
        expect(failure.offline, isFalse, reason: failure.title);
        expect(failure.title, isNotEmpty);
        expect(failure.message, isNotEmpty);
      }
    });

    test('a locked vault is named as such, not as a key load failure', () {
      const failure = ChatFailure.vaultLocked();

      expect(failure.title, contains('vault'));
      expect(failure.message, contains('Unlock'));
    });
  });
}
