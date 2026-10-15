import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rift/data/central_failure.dart';
import 'package:rift/data/central_http_client.dart';

/// A central that takes [delay] to answer anything.
http.Client _slow(Duration delay) => MockClient((request) async {
  await Future<void>.delayed(delay);
  return http.Response('{}', 200);
});

void main() {
  const limit = Duration(milliseconds: 50);
  final url = Uri.parse('https://central.test/rest/v1/rpc/send_dm');

  test('a small request with no answer gives up, in words', () async {
    final client = CentralHttpClient(
      inner: _slow(const Duration(seconds: 2)),
      answerWithin: limit,
    );
    final call = client.post(url, body: '{"recipient":"x"}');
    await expectLater(call, throwsA(isA<TimeoutException>()));
    await expectLater(
      client.get(url),
      throwsA(predicate<Object>(CentralFailure.isUnreachable)),
    );
  });

  test('an answer inside the limit comes through', () async {
    final client = CentralHttpClient(
      inner: _slow(Duration.zero),
      answerWithin: limit,
    );
    expect((await client.get(url)).statusCode, 200);
  });

  test('an upload is never cut off', () async {
    final client = CentralHttpClient(
      inner: _slow(const Duration(milliseconds: 200)),
      answerWithin: limit,
    );
    final body = List<int>.filled(CentralHttpClient.smallBody + 1, 0);
    expect((await client.put(url, body: body)).statusCode, 200);
  });
}
