import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rift/data/repositories/server_repository.dart';

/// A server's anon key lets a sign-in go straight to GoTrue's web3 grant; the
/// `login` function is for the first join, which has none, and for a key the
/// gateway no longer takes.
void main() {
  final session = {'access_token': 'at', 'refresh_token': 'rt'};

  ({ServerRepository repo, List<http.Request> asked}) server({
    int grantStatus = 200,
    Map<String, dynamic>? grantBody,
  }) {
    final asked = <http.Request>[];
    final repo = ServerRepository(
      askAgainAfter: Duration.zero,
      client: MockClient((request) async {
        asked.add(request);
        if (request.url.path == '/auth/v1/token') {
          return http.Response(
            jsonEncode(grantBody ?? session),
            grantStatus,
            headers: {
              'content-type': 'application/json',
              'date': 'Thu, 26 Nov 2026 12:00:00 GMT',
            },
            request: request,
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'data': session}),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    return (repo: repo, asked: asked);
  }

  test('with the anon key, GoTrue is asked and the function is not', () async {
    final s = server();
    final response = await s.repo.login(
      'https://srv.example',
      message: 'm',
      signature: 'sig',
      anonKey: 'anon',
    );
    expect(response.success, isTrue);
    expect((response.data as Map)['access_token'], 'at');
    expect(s.asked, hasLength(1));
    final grant = s.asked.single;
    expect(grant.url.queryParameters['grant_type'], 'web3');
    expect(grant.headers['apikey'], 'anon');
    expect(jsonDecode(grant.body), {
      'chain': 'solana',
      'message': 'm',
      'signature': 'sig',
    });
  });

  test('without a key, or with one the gateway refuses, the function is '
      'asked', () async {
    final none = server();
    await none.repo.login('https://srv.example', message: 'm', signature: 's');
    expect(none.asked.map((r) => r.url.path), ['/functions/v1/login']);

    final refused = server(
      grantStatus: 401,
      grantBody: {'message': 'Invalid authentication credentials'},
    );
    final response = await refused.repo.login(
      'https://srv.example',
      message: 'm',
      signature: 's',
      anonKey: 'old',
    );
    expect(response.success, isTrue);
    expect(refused.asked.map((r) => r.url.path), [
      '/auth/v1/token',
      '/functions/v1/login',
    ]);
  });

  test('a refusal is GoTrue\'s own words, with its time', () async {
    final s = server(
      grantStatus: 400,
      grantBody: {
        'code': 400,
        'error_code': 'validation_failed',
        'msg': 'signature issued too far in the future',
      },
    );
    final response = await s.repo.login(
      'https://srv.example',
      message: 'm',
      signature: 's',
      anonKey: 'anon',
    );
    expect(response.success, isFalse);
    expect(response.error, 'signature issued too far in the future');
    expect(response.errorCode, 'signature_invalid');
    expect(response.serverTime, DateTime.utc(2026, 11, 26, 12));
    expect(s.asked, hasLength(1));
  });
}
