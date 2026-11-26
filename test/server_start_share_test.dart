import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rift/data/enums/error_code.dart';
import 'package:rift/data/repositories/server_repository.dart';

/// Self-host 064: a server's first loads share one `server_start`, its DM
/// lists are one `dm_lists`, and its console sweeps attachments itself. A
/// server older than that answers `PGRST202` once and is asked the old way.
void main() {
  const url = 'https://srv.example';
  final start = {
    'unread': {'channels': {}, 'dms': {}, 'prefs': {}},
    'sidebar': {
      'bots': [],
      'people': [],
      'counts': {'people': 0, 'bots': 0},
      'roles': [],
      'assignments': [],
    },
    'sounds': [
      {'id': 's1', 'name': 'boop', 'object_path': 'x/boop.audio'},
    ],
    'listeners': [
      {'channel_id': 'c', 'bot_id': 'b', 'bot_name': 'Beep'},
    ],
    'summons': [],
    'sweeps_itself': true,
  };

  http.Response json(http.Request request, Object body, [int status = 200]) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );

  ({ServerRepository repo, List<String> asked}) server({required bool is064}) {
    final asked = <String>[];
    final repo = ServerRepository(
      askAgainAfter: Duration.zero,
      client: MockClient((request) async {
        final path = request.url.path;
        asked.add(path);
        final missing = {
          'code': 'PGRST202',
          'message': 'Could not find the function',
        };
        switch (path) {
          case '/rest/v1/rpc/server_start':
            return is064 ? json(request, start) : json(request, missing, 404);
          case '/rest/v1/rpc/dm_lists':
            return json(request, missing, 404);
          case '/rest/v1/rpc/get_server_details':
            return json(request, {
              'user': {'id': 'me', 'chat_public_key': 'K'},
            });
          case '/rest/v1/rpc/member_sidebar':
            return json(request, start['sidebar']!);
          case '/rest/v1/rpc/unread_counts':
            return json(request, start['unread']!);
          case '/functions/v1/sweep_attachments':
            return json(request, {
              'success': true,
              'data': {'swept': 0, 'more': false},
            });
        }
        return json(request, []);
      }),
    );
    return (repo: repo, asked: asked);
  }

  Future<List<dynamic>> firstLoads(
    ServerRepository repo, [
    String token = 't',
  ]) => Future.wait([
    repo.unreadCounts(url, anonKey: 'a', bearerToken: token, first: true),
    repo.memberSidebar(url, anonKey: 'a', bearerToken: token, first: true),
    repo.listSounds(url, anonKey: 'a', bearerToken: token, first: true),
    repo.listVoiceListeners(url, anonKey: 'a', bearerToken: token, first: true),
    repo.listVoiceSummons(url, anonKey: 'a', bearerToken: token, first: true),
  ]);

  test('first loads share one server_start, each taking its part', () async {
    final s = server(is064: true);
    final answers = await firstLoads(s.repo);
    expect(s.asked, ['/rest/v1/rpc/server_start']);
    expect(answers.every((a) => a.success == true), isTrue);
    expect((answers[2].data as Map)['sounds'], hasLength(1));
    expect(
      ((answers[3].data as Map)['listeners'] as List).single['bot_name'],
      'Beep',
    );
    expect((answers[1].data as Map)['people'], {
      'users': [],
      'has_more': false,
    });

    // A read that is not a first load is its own call, and so is a part
    // already taken.
    s.asked.clear();
    await s.repo.unreadCounts(url, anonKey: 'a', bearerToken: 't');
    await s.repo.unreadCounts(url, anonKey: 'a', bearerToken: 't', first: true);
    expect(s.asked, [
      '/rest/v1/rpc/unread_counts',
      '/rest/v1/rpc/unread_counts',
    ]);

    // The console sweeps: nothing to ask.
    s.asked.clear();
    await s.repo.sweepAttachments(url, bearerToken: 't');
    expect(s.asked, isEmpty);
  });

  test(
    'an older server is asked server_start once, then the old way',
    () async {
      final s = server(is064: false);
      final answers = await firstLoads(s.repo);
      expect(answers.every((a) => a.success == true), isTrue);
      expect(s.asked.first, '/rest/v1/rpc/server_start');
      expect(
        s.asked.where((p) => p == '/rest/v1/rpc/server_start'),
        hasLength(1),
      );
      expect(s.asked, contains('/rest/v1/rpc/member_sidebar'));

      s.asked.clear();
      await s.repo.unreadCounts(
        url,
        anonKey: 'a',
        bearerToken: 't2',
        first: true,
      );
      await s.repo.sweepAttachments(url, bearerToken: 't2');
      expect(s.asked, [
        '/rest/v1/rpc/unread_counts',
        '/functions/v1/sweep_attachments',
      ]);

      // dm_lists likewise: asked once, then not.
      s.asked.clear();
      final first = await s.repo.dmLists(url, anonKey: 'a', bearerToken: 't2');
      final again = await s.repo.dmLists(url, anonKey: 'a', bearerToken: 't2');
      expect(first.errorCode, 'PGRST202');
      expect(again.errorCode, 'PGRST202');
      expect(s.asked, ['/rest/v1/rpc/dm_lists']);
    },
  );

  test('a chat key the details already named is not read again', () async {
    final s = server(is064: true);
    await s.repo.getServerDetails(url, anonKey: 'a', bearerToken: 't');
    s.asked.clear();
    final same = await s.repo.publishChatKey(
      url,
      anonKey: 'a',
      bearerToken: 't',
      userId: 'me',
      chatPublicKey: 'K',
    );
    expect(same.success, isTrue);
    expect(s.asked, isEmpty);

    await s.repo.publishChatKey(
      url,
      anonKey: 'a',
      bearerToken: 't',
      userId: 'me',
      chatPublicKey: 'K2',
    );
    expect(s.asked, isNotEmpty);
  });

  test('a token the server no longer takes is every part\'s answer, and '
      'the retry under a new one is one server_start again', () async {
    final asked = <String>[];
    final repo = ServerRepository(
      askAgainAfter: Duration.zero,
      client: MockClient((request) async {
        asked.add(request.url.path);
        if (request.headers['Authorization'] == 'Bearer old') {
          return json(request, {
            'code': 'PGRST303',
            'message': 'JWT expired',
          }, 401);
        }
        if (request.url.path == '/rest/v1/rpc/server_start') {
          return json(request, start);
        }
        return json(request, []);
      }),
    );

    final refused = await firstLoads(repo, 'old');
    expect(asked, ['/rest/v1/rpc/server_start']);
    expect(refused.every((a) => a.errorCode == ErrorCode.tokenExpired), isTrue);

    // Signed in again, at once: inside the gap a stale answer keeps.
    asked.clear();
    final answers = await firstLoads(repo, 'new');
    expect(asked, ['/rest/v1/rpc/server_start']);
    expect(answers.every((a) => a.success == true), isTrue);
  });

  test('two servers at one URL each share their own server_start', () async {
    final s = server(is064: true);
    await Future.wait([firstLoads(s.repo, 'one'), firstLoads(s.repo, 'two')]);
    expect(s.asked, ['/rest/v1/rpc/server_start', '/rest/v1/rpc/server_start']);
  });
}
