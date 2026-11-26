import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rift/data/classes/sealed_keys.dart';
import 'package:rift/data/repositories/server_repository.dart';

/// Sealed keys are stored by database calls since self-host 077
/// (`store_channel_keys`, and a sweep pass at once by `store_key_work`). A
/// server older than that answers PGRST202 and is posted each batch through
/// `post_channel_keys` from then on.
void main() {
  SealedKeys batch(String channel, int entries, {bool mint = false}) =>
      SealedKeys(
        channelId: channel,
        keyVersion: 1,
        entries: [
          for (var i = 0; i < entries; i++)
            {
              'user_id': 'u$i',
              'ephemeral_public_key': 'e',
              'ciphertext': 'c',
              'nonce': 'n',
            },
        ],
        mint: mint,
      );

  ({ServerRepository repo, List<String> asked, List<Object?> bodies}) server({
    required bool hasRpc,
  }) {
    final asked = <String>[];
    final bodies = <Object?>[];
    http.Response json(Object body, int status, http.Request request) =>
        http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
    final repo = ServerRepository(
      askAgainAfter: Duration.zero,
      client: MockClient((request) async {
        final path = request.url.path;
        asked.add(path);
        final body = jsonDecode(request.body);
        bodies.add(body);
        if (path.startsWith('/rest/v1/rpc/')) {
          if (!hasRpc) {
            return json(
              {'code': 'PGRST202', 'message': 'Could not find the function'},
              404,
              request,
            );
          }
          if (path.endsWith('store_key_work')) {
            final jobs = (body as Map)['p_jobs'] as List;
            return json(
              {
                'results': [
                  for (final job in jobs)
                    {
                      'channel_id': job['channel_id'],
                      'key_version': job['key_version'],
                      'success': true,
                    },
                ],
              },
              200,
              request,
            );
          }
          return json({'channel_id': 'c1', 'entries_stored': 1}, 200, request);
        }
        final channel = (body as Map)['channel_id'];
        return channel == 'lost'
            ? json(
                {
                  'success': false,
                  'error': 'refetch',
                  'code': 'keyring_conflict',
                },
                200,
                request,
              )
            : json(
                {
                  'success': true,
                  'data': {'channel_id': channel},
                },
                200,
                request,
              );
      }),
    );
    return (repo: repo, asked: asked, bodies: bodies);
  }

  test('a server with the calls is asked them, a pass at once', () async {
    final s = server(hasRpc: true);
    final one = await s.repo.postChannelKeys(
      'https://new.example',
      anonKey: 'anon',
      bearerToken: 't',
      keys: batch('c1', 1, mint: true),
    );
    expect(one.success, isTrue);
    expect(s.asked, ['/rest/v1/rpc/store_channel_keys']);
    expect((s.bodies.single as Map)['p_mint'], isTrue);

    s.asked.clear();
    final pass = await s.repo.storeKeyWork(
      'https://new.example',
      anonKey: 'anon',
      bearerToken: 't',
      batches: [batch('c1', 2), batch('c2', 3), batch('c3', 1)],
    );
    expect(s.asked, ['/rest/v1/rpc/store_key_work']);
    final results = (pass.data as Map)['results'] as List;
    expect(results.map((r) => r['channel_id']), ['c1', 'c2', 'c3']);
  });

  test('a pass bigger than the server takes goes in two', () async {
    final s = server(hasRpc: true);
    final pass = await s.repo.storeKeyWork(
      'https://new.example',
      anonKey: 'anon',
      bearerToken: 't',
      batches: [batch('c1', 300), batch('c2', 300)],
    );
    expect(s.asked, [
      '/rest/v1/rpc/store_key_work',
      '/rest/v1/rpc/store_key_work',
    ]);
    expect(((pass.data as Map)['results'] as List).length, 2);
  });

  test('an older server is posted each batch, and not asked again', () async {
    final s = server(hasRpc: false);
    final pass = await s.repo.storeKeyWork(
      'https://old.example',
      anonKey: 'anon',
      bearerToken: 't',
      batches: [batch('c1', 1), batch('lost', 1, mint: true)],
    );
    expect(s.asked, [
      '/rest/v1/rpc/store_key_work',
      '/functions/v1/post_channel_keys',
      '/functions/v1/post_channel_keys',
    ]);
    final results = ((pass.data as Map)['results'] as List)
        .cast<Map<String, dynamic>>();
    expect(results[0]['success'], isTrue);
    expect(results[1]['success'], isFalse);
    expect(results[1]['code'], 'keyring_conflict');

    s.asked.clear();
    await s.repo.postChannelKeys(
      'https://old.example',
      anonKey: 'anon',
      bearerToken: 't',
      keys: batch('c1', 1),
    );
    expect(s.asked, ['/functions/v1/post_channel_keys']);
    expect((s.bodies.last as Map)['mint'], isFalse);
  });
}
