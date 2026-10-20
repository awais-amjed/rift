import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rift/data/enums/error_code.dart';
import 'package:rift/data/repositories/server_repository.dart';

/// The functions always answer 200, so any other status is the gateway in
/// front of them speaking. On Oct 19 2026 the runtime ran out of memory on a
/// first voice join, the gateway answered 502 with no envelope, and the app
/// said "Unknown error" where a second try moments later worked.
void main() {
  final ok = jsonEncode({
    'success': true,
    'data': {'token': 't'},
  });

  ({ServerRepository repo, List<int> asked}) serverAnswering(
    List<int> statuses,
  ) {
    final asked = <int>[];
    final repo = ServerRepository(
      askAgainAfter: Duration.zero,
      client: MockClient((request) async {
        final status = statuses[asked.length];
        asked.add(status);
        return http.Response(status == 200 ? ok : '', status);
      }),
    );
    return (repo: repo, asked: asked);
  }

  test('a runtime back by the second try answers it', () async {
    for (final status in [500, 502, 503]) {
      final server = serverAnswering([status, 200]);
      final response = await server.repo.getChannelToken('https://s', 'c');
      expect(response.success, isTrue, reason: '$status');
      expect(server.asked, [status, 200]);
    }
  });

  test('a runtime still down is trouble, not an unknown error', () async {
    final server = serverAnswering([502, 502]);
    final response = await server.repo.getChannelToken('https://s', 'c');
    expect(response.success, isFalse);
    expect(response.errorCode, ErrorCode.serverTimeout);
    expect(response.error, contains('having trouble'));
    expect(server.asked, hasLength(2));
  });

  test('a call the gateway gave up waiting on is not sent again', () async {
    // The function may still be running, and a second one could write twice.
    final server = serverAnswering([504]);
    final response = await server.repo.getChannelToken('https://s', 'c');
    expect(response.errorCode, ErrorCode.serverTimeout);
    expect(server.asked, [504]);
  });
}
