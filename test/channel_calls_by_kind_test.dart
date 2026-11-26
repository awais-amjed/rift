import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rift/data/apis/channel_access_api.dart';
import 'package:rift/data/apis/channels_api.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';

/// A voice channel's member changes, leaving and deleting go through edge
/// functions, because a call running there has to be told. A text channel
/// has no call, so the same acts are the database calls those functions
/// make: the RPC, and the row delete under its policy.
void main() {
  const url = 'https://kinds.example';

  ({SessionRepository session, List<String> asked}) server({
    bool hasMemberRpc = true,
    bool deletes = true,
  }) {
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
        asked.add('${request.method} $path');
        if (path == '/rest/v1/rpc/change_channel_members' && !hasMemberRpc) {
          return json(
            {'code': 'PGRST202', 'message': 'Could not find the function'},
            404,
            request,
          );
        }
        if (path == '/rest/v1/channels') {
          return json(
            deletes
                ? [
                    {'id': 'c1'},
                  ]
                : [],
            200,
            request,
          );
        }
        if (path.startsWith('/functions/v1/')) {
          return json(
            {
              'success': true,
              'data': {'reason': 'ok'},
            },
            200,
            request,
          );
        }
        return json({'reason': 'ok'}, 200, request);
      }),
    );
    final session = SessionRepository(servers: repo)
      ..publish(
        servers: [
          Server(
            id: 's1',
            name: 'Kinds',
            supabaseUrl: url,
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
    return (session: session, asked: asked);
  }

  test('a text channel is the database calls', () async {
    final s = server();
    final access = ChannelAccessApi(s.session.on('s1'));
    expect(
      (await access.changeChannelMembers(
        channelId: 'c1',
        isVoice: false,
        add: {'u1'},
        remove: const {},
        seated: {'me'},
      )).success,
      isTrue,
    );
    expect((await access.leaveChannel('c1', isVoice: false)).success, isTrue);
    expect(
      (await ChannelsApi(
        s.session.on('s1'),
      ).deleteChannel('c1', isVoice: false)).success,
      isTrue,
    );
    expect(s.asked, [
      'POST /rest/v1/rpc/change_channel_members',
      'POST /rest/v1/rpc/leave_channel',
      'DELETE /rest/v1/channels',
    ]);
  });

  test('a voice channel goes through the functions', () async {
    final s = server();
    final access = ChannelAccessApi(s.session.on('s1'));
    await access.changeChannelMembers(
      channelId: 'c1',
      isVoice: true,
      add: {'u1'},
      remove: const {},
      seated: {'me'},
    );
    await access.leaveChannel('c1', isVoice: true);
    await ChannelsApi(s.session.on('s1')).deleteChannel('c1', isVoice: true);
    expect(s.asked, [
      'POST /functions/v1/change_channel_members',
      'POST /functions/v1/change_channel_members',
      'POST /functions/v1/delete_channel',
    ]);
  });

  test('a server without the member call gets the whole list', () async {
    final s = server(hasMemberRpc: false);
    final result = await ChannelAccessApi(s.session.on('s1'))
        .changeChannelMembers(
          channelId: 'c1',
          isVoice: false,
          add: {'u1'},
          remove: const {},
          seated: {'me'},
        );
    expect(result.success, isTrue);
    expect(s.asked, [
      'POST /rest/v1/rpc/change_channel_members',
      'POST /rest/v1/rpc/set_channel_members',
    ]);
  });

  test('a delete the policy refused is said so', () async {
    final s = server(deletes: false);
    final result = await ChannelsApi(
      s.session.on('s1'),
    ).deleteChannel('c1', isVoice: false);
    expect(result.success, isFalse);
    expect(result.error, contains('permission'));
  });
}
