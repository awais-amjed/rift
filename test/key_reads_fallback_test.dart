import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rift/data/repositories/server_repository.dart';

/// A channel's keys and the sweep's work are database calls since self-host
/// 063 (`my_channel_key`, `my_key_work`). A server older than that answers
/// PGRST202, and is asked through the edge functions from then on.
void main() {
  final keys = {'current_version': 2, 'my_keys': [], 'links': []};

  ({ServerRepository repo, List<String> asked}) server({required bool hasRpc}) {
    final asked = <String>[];
    final repo = ServerRepository(
      askAgainAfter: Duration.zero,
      client: MockClient((request) async {
        final path = request.url.path;
        asked.add(path);
        if (path.startsWith('/rest/v1/rpc/')) {
          return hasRpc
              ? http.Response(
                  jsonEncode(keys),
                  200,
                  headers: {'content-type': 'application/json'},
                  request: request,
                )
              : http.Response(
                  jsonEncode({
                    'code': 'PGRST202',
                    'message': 'Could not find the function',
                  }),
                  404,
                  headers: {'content-type': 'application/json'},
                  request: request,
                );
        }
        return http.Response(
          jsonEncode({'success': true, 'data': keys}),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    return (repo: repo, asked: asked);
  }

  test('a server with the call is asked it, and nothing else', () async {
    final s = server(hasRpc: true);
    final response = await s.repo.getChannelKey(
      'https://new.example',
      anonKey: 'anon',
      bearerToken: 't',
      channelId: 'c',
    );
    expect(response.success, isTrue);
    expect((response.data as Map)['current_version'], 2);
    expect(s.asked, ['/rest/v1/rpc/my_channel_key']);

    await s.repo.sweepChannelKeys(
      'https://new.example',
      anonKey: 'anon',
      bearerToken: 't',
    );
    expect(s.asked.last, '/rest/v1/rpc/my_key_work');
  });

  test('an older server falls back, and is not asked the call again', () async {
    final s = server(hasRpc: false);
    final first = await s.repo.getChannelKey(
      'https://old.example',
      anonKey: 'anon',
      bearerToken: 't',
      channelId: 'c',
    );
    expect(first.success, isTrue);
    expect((first.data as Map)['current_version'], 2);
    expect(s.asked, [
      '/rest/v1/rpc/my_channel_key',
      '/functions/v1/get_channel_key',
    ]);

    s.asked.clear();
    await s.repo.getChannelKey(
      'https://old.example',
      anonKey: 'anon',
      bearerToken: 't',
      channelId: 'c',
    );
    await s.repo.sweepChannelKeys(
      'https://old.example',
      anonKey: 'anon',
      bearerToken: 't',
    );
    expect(s.asked, [
      '/functions/v1/get_channel_key',
      '/functions/v1/sweep_channel_keys',
    ]);
  });
}
