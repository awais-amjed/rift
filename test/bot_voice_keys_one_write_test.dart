import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rift/data/apis/voice_bots_api.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// The bots short of a key in a call are sealed theirs in one write. The
/// policy judges each row, so a batch it refuses is sent again a bot at a
/// time and the others still get theirs.
void main() {
  ({VoiceBotsApi api, List<List<Object?>> writes}) server({String? refuse}) {
    final writes = <List<Object?>>[];
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
        if (path != '/rest/v1/bot_voice_keys') {
          return json({'message': 'not here'}, 500, request);
        }
        final rows = (jsonDecode(request.body) as List).cast<Map>();
        writes.add([for (final row in rows) row['bot_id']]);
        if (refuse != null && rows.any((row) => row['bot_id'] == refuse)) {
          return json(
            {'code': '42501', 'message': 'row-level security'},
            403,
            request,
          );
        }
        return json([], 201, request);
      }),
    );
    final session = SessionRepository(servers: repo)
      ..publish(
        servers: [
          Server(
            id: 's1',
            name: 'Bots',
            supabaseUrl: 'https://bots.example',
            supabaseKey: 'anon',
            token: 'token',
            user: const ServerUser(
              id: 'me',
              username: 'me',
              displayName: 'Me',
              permissions: UserPermissions(),
            ),
          ),
        ],
        selectedServerId: 's1',
      );
    return (api: VoiceBotsApi(session.on('s1')), writes: writes);
  }

  BotVoiceKey key(String bot) => BotVoiceKey(
    botId: bot,
    isChannelKey: false,
    wrapped: const WrappedKey(
      ephemeralPublicKey: 'e',
      ciphertext: 'c',
      nonce: 'n',
    ),
  );

  test('every bot in one write', () async {
    final s = server();
    await s.api.postBotVoiceKeys(
      channelId: 'v1',
      keyVersion: 3,
      keys: [key('b1'), key('b2'), key('b3')],
    );
    expect(s.writes, [
      ['b1', 'b2', 'b3'],
    ]);
  });

  test('a refused batch is sent again a bot at a time', () async {
    final s = server(refuse: 'b2');
    await s.api.postBotVoiceKeys(
      channelId: 'v1',
      keyVersion: 3,
      keys: [key('b1'), key('b2'), key('b3')],
    );
    expect(s.writes, [
      ['b1', 'b2', 'b3'],
      ['b1'],
      ['b2'],
      ['b3'],
    ]);
  });
}
