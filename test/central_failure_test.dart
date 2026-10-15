import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rift/data/central_failure.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/enums/error_code.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide ErrorCode;

void main() {
  group('CentralFailure.isUnreachable', () {
    test('a sign-in that never reached central', () {
      // What a new user saw on the sign-in form while central was down.
      final e = AuthRetryableFetchException(
        message:
            'ClientException with SocketException: Connection refused '
            '(OS Error: Connection refused, errno = 111), '
            'address = api.joinrift.app, port = 443',
      );
      expect(CentralFailure.isUnreachable(e), isTrue);
    });

    test('the gateway answering for a service that is down', () {
      expect(
        CentralFailure.isUnreachable(
          AuthRetryableFetchException(message: '', statusCode: '502'),
        ),
        isTrue,
      );
      expect(
        CentralFailure.isUnreachable(
          const PostgrestException(message: '', code: '503'),
        ),
        isTrue,
      );
      expect(
        CentralFailure.isUnreachable(StorageException('', statusCode: '504')),
        isTrue,
      );
      expect(
        CentralFailure.isUnreachable(const FunctionException(status: 502)),
        isTrue,
      );
    });

    test('a request that failed before any answer', () {
      expect(
        CentralFailure.isUnreachable(
          StorageException(
            'ClientException with SocketException: Network is unreachable',
            statusCode: 'ClientException',
          ),
        ),
        isTrue,
      );
      expect(
        CentralFailure.isUnreachable(http.ClientException('Connection reset')),
        isTrue,
      );
      expect(
        CentralFailure.isUnreachable(
          const SocketException('Failed host lookup'),
        ),
        isTrue,
      );
      expect(CentralFailure.isUnreachable(TimeoutException('slow')), isTrue);
    });

    test('central answering no keeps its own words', () {
      // GoTrue's own failure, which its message explains.
      expect(
        CentralFailure.isUnreachable(
          AuthRetryableFetchException(
            message: 'Error sending confirmation email',
            statusCode: '500',
          ),
        ),
        isFalse,
      );
      expect(
        CentralFailure.isUnreachable(
          AuthApiException(
            'Invalid login credentials',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
        ),
        isFalse,
      );
      // A SQLSTATE, not an HTTP status.
      expect(
        CentralFailure.isUnreachable(
          const PostgrestException(message: 'quota_exceeded', code: 'P0001'),
        ),
        isFalse,
      );
      expect(
        CentralFailure.isUnreachable(
          StorageException('Object not found', statusCode: '404'),
        ),
        isFalse,
      );
      expect(CentralFailure.isUnreachable(StateError('bug')), isFalse);
    });
  });

  group('CentralFailure.response', () {
    test('says it in words, with a code that can be retried', () {
      final r = CentralFailure.response(
        AuthRetryableFetchException(message: 'ClientException'),
      );
      expect(r.success, isFalse);
      expect(r.error, CentralFailure.message);
      expect(r.errorCode, ErrorCode.serverUnreachable);
      expect(ErrorCode.isRetryable(r.errorCode), isTrue);
    });

    test('a timeout says the same, coded as a timeout', () {
      final r = CentralFailure.response(TimeoutException('slow'));
      expect(r.error, CentralFailure.message);
      expect(r.errorCode, ErrorCode.serverTimeout);
    });

    test('anything else passes through', () {
      final e = StateError('bug');
      final r = CentralFailure.response(e);
      expect(r.error, APIResponse.error(e).error);
      expect(r.errorCode, isNull);
    });
  });
}
