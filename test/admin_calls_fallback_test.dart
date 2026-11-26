import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rift/data/enums/error_code.dart';
import 'package:rift/data/repositories/server_repository.dart';

/// Push settings and the listing token are database calls since self-host
/// 080 (`push_status`, `set_push_config`, `clear_push_config`,
/// `my_listing_token`). A server older than that answers PGRST202 and is
/// asked the edge functions from then on. A summon is the RPC on every
/// server.
void main() {
  ({ServerRepository repo, List<String> asked, List<Object?> bodies}) server({
    required bool hasRpc,
    bool admin = true,
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
        bodies.add(request.body.isEmpty ? null : jsonDecode(request.body));
        if (path.startsWith('/rest/v1/rpc/')) {
          final rpc = path.substring('/rest/v1/rpc/'.length);
          if (!hasRpc && rpc != 'summon_bot_to_voice') {
            return json(
              {'code': 'PGRST202', 'message': 'Could not find the function'},
              404,
              request,
            );
          }
          if (!admin) {
            return json(
              {'code': 'P0001', 'message': 'permission_denied'},
              400,
              request,
            );
          }
          return json(
            switch (rpc) {
              'push_status' => {'enabled': true, 'relay_id': 'r1'},
              'clear_push_config' => {'enabled': false, 'relay_id': 'r1'},
              'my_listing_token' => {'token': 't0k', 'server_id': 's1'},
              'summon_bot_to_voice' => {
                'reason': 'ok',
                'new': false,
                'needs_key': false,
              },
              _ => {'enabled': true},
            },
            200,
            request,
          );
        }
        return json(
          {
            'success': true,
            'data': {'enabled': true, 'relay_id': 'r1', 'token': 'edge'},
          },
          200,
          request,
        );
      }),
    );
    return (repo: repo, asked: asked, bodies: bodies);
  }

  test('a server with the calls is asked them', () async {
    final s = server(hasRpc: true);
    final status = await s.repo.pushStatus(
      'https://new.example',
      anonKey: 'anon',
      bearerToken: 't',
    );
    expect((status.data as Map)['relay_id'], 'r1');
    await s.repo.configurePush(
      'https://new.example',
      anonKey: 'anon',
      bearerToken: 't',
      endpoint: 'https://relay.example/forward',
      relayId: 'r1',
      secret: 'secret-secret-secret',
    );
    await s.repo.disablePush(
      'https://new.example',
      anonKey: 'anon',
      bearerToken: 't',
    );
    final token = await s.repo.listingToken(
      'https://new.example',
      anonKey: 'anon',
      bearerToken: 't',
    );
    expect((token.data as Map)['token'], 't0k');
    expect(s.asked, [
      '/rest/v1/rpc/push_status',
      '/rest/v1/rpc/set_push_config',
      '/rest/v1/rpc/clear_push_config',
      '/rest/v1/rpc/my_listing_token',
    ]);
    expect((s.bodies[1] as Map)['p_relay_id'], 'r1');
  });

  test(
    'an older server is asked the edge functions, and not the calls again',
    () async {
      final s = server(hasRpc: false);
      await s.repo.pushStatus(
        'https://old.example',
        anonKey: 'anon',
        bearerToken: 't',
      );
      await s.repo.disablePush(
        'https://old.example',
        anonKey: 'anon',
        bearerToken: 't',
      );
      final token = await s.repo.listingToken(
        'https://old.example',
        anonKey: 'anon',
        bearerToken: 't',
      );
      expect((token.data as Map)['token'], 'edge');
      expect(s.asked, [
        '/rest/v1/rpc/push_status',
        '/functions/v1/configure_push',
        '/functions/v1/configure_push',
        '/rest/v1/rpc/my_listing_token',
        '/functions/v1/listing_token',
      ]);
      expect(s.bodies[1], {'status': true});
      expect(s.bodies[2], {'disable': true});
    },
  );

  test('a member is refused in words', () async {
    final s = server(hasRpc: true, admin: false);
    final status = await s.repo.pushStatus(
      'https://new.example',
      anonKey: 'anon',
      bearerToken: 't',
    );
    expect(status.success, isFalse);
    expect(status.errorCode, ErrorCode.permissionDenied);
    expect(status.error, contains('server admins'));
    final token = await s.repo.listingToken(
      'https://new.example',
      anonKey: 'anon',
      bearerToken: 't',
    );
    expect(token.error, contains('server admin'));
  });

  test('a summon is the database call', () async {
    final s = server(hasRpc: false);
    final summoned = await s.repo.summonBotToVoice(
      'https://old.example',
      anonKey: 'anon',
      bearerToken: 't',
      channelId: 'c1',
      botId: 'b1',
    );
    expect(s.asked, ['/rest/v1/rpc/summon_bot_to_voice']);
    expect(s.bodies.single, {'p_bot': 'b1', 'p_channel': 'c1'});
    expect((summoned.data as Map)['needs_key'], isFalse);
  });
}
