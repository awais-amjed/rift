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

/// A `voice_bots` ring is one read since self-host 084 (`voice_bots`), the
/// listeners and the summons together. A server older than that answers
/// PGRST202 and is read the two views apart from then on.
void main() {
  ({VoiceBotsApi api, List<String> asked}) server({required bool hasRpc}) {
    final asked = <String>[];
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
        if (path.endsWith('get_server_details')) {
          return json({'message': 'not here'}, 500, request);
        }
        asked.add(path);
        if (path == '/rest/v1/rpc/voice_bots') {
          if (!hasRpc) {
            return json(
              {'code': 'PGRST202', 'message': 'Could not find the function'},
              404,
              request,
            );
          }
          return json(
            {
              'listeners': [
                {'channel_id': 'v1', 'bot_id': 'b1', 'bot_name': 'Ear'},
              ],
              'summons': [
                {'channel_id': 'v2', 'bot_id': 'b2', 'bot_name': 'Tune'},
              ],
            },
            200,
            request,
          );
        }
        return json([], 200, request);
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
    return (api: VoiceBotsApi(session.on('s1')), asked: asked);
  }

  test('a server with the call answers both in one read', () async {
    final s = server(hasRpc: true);
    final both = await s.api.voiceBotsByChannel();
    expect(s.asked, ['/rest/v1/rpc/voice_bots']);
    expect(both!.listeners!['v1']!.single, (id: 'b1', name: 'Ear'));
    expect(both.summons!['v2']!.single, (id: 'b2', name: 'Tune'));
  });

  test('an older server says so, and is not asked again', () async {
    final s = server(hasRpc: false);
    expect(await s.api.voiceBotsByChannel(), isNull);
    expect(await s.api.voiceBotsByChannel(), isNull);
    expect(s.asked, ['/rest/v1/rpc/voice_bots']);
  });
}
