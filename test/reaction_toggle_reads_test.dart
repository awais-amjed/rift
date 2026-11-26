import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/member_page.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/auth_status.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/channel_chat/channel_chat_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift/logic/services/message_cache.dart';
import 'package:rift/logic/services/server_topics.dart';

/// Self-host 067: a reaction is one `toggle_reaction` request, which answers
/// the counts, and its own ring back asks nothing. Anybody else's ring, and
/// one from another of our devices, still reads the counts; a server from
/// before it is read after the tap and on every ring, as it was.

class _Reads extends ServerRepository {
  _Reads({required this.is067});

  final bool is067;
  final List<String> asked = [];

  static final _key = APIResponse.success(const {
    'current_version': 1,
    'my_keys': [],
    'links': [],
    'members_missing': [],
    'bots_missing': [],
    'my_voice_key': null,
  });

  @override
  Future<APIResponse> openChannel(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String channelId,
    int? limit,
  }) async {
    return APIResponse.success({
      'page': {'messages': <dynamic>[], 'has_more': false},
      'live': {'messages': <dynamic>[]},
      'key': _key.data,
      'key_error': null,
      'listeners': <dynamic>[],
      'bots': {'users': <dynamic>[], 'has_more': false},
    });
  }

  @override
  Future<APIResponse> listMessages(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String channelId,
    int? beforeId,
    int? afterId,
    int? limit,
  }) async {
    asked.add('channel_messages');
    return APIResponse.success({'messages': <dynamic>[], 'has_more': false});
  }

  @override
  Future<APIResponse> listLiveMessages(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String channelId,
  }) async {
    asked.add('channel_live_messages');
    return APIResponse.success({'messages': <dynamic>[]});
  }

  @override
  Future<APIResponse> listChannelListeners(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
  }) async {
    asked.add('channel_bot_listeners');
    return APIResponse.success({'listeners': <dynamic>[]});
  }

  @override
  Future<APIResponse> listMembers(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    String? channelId,
    bool? bots,
    bool? banned = false,
    String? afterName,
    String? afterId,
    int limit = MemberPage.pageSize,
  }) async {
    asked.add('list_members');
    return APIResponse.success({'users': <dynamic>[], 'has_more': false});
  }

  @override
  Future<APIResponse> getChannelKey(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
  }) async {
    asked.add('my_channel_key');
    return _key;
  }

  @override
  Future<APIResponse> publishChatKey(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String chatPublicKey,
  }) async =>
      APIResponse.success({'published': true, publishedChatKeyIsNew: false});

  @override
  Future<APIResponse> sweepChannelKeys(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) async => APIResponse.success(const {'work': [], 'more': false});

  static const _counts = [
    {'emoji': '👍', 'count': 1, 'mine': true},
  ];

  @override
  Future<APIResponse> toggleReaction(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String scope,
    required int messageId,
    required String emoji,
  }) async {
    asked.add('toggle_reaction');
    // A server from before 067 is written row by row and answers no counts.
    return APIResponse.success({'reacted': true, if (is067) 'counts': _counts});
  }

  @override
  Future<APIResponse> listReactions(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String scope,
    required List<int> messageIds,
  }) async {
    asked.add('message_reaction_tallies');
    return APIResponse.success({
      'reactions': {'${messageIds.first}': _counts},
    });
  }

  @override
  Future<APIResponse> sweepAttachments(
    String supabaseUrl, {
    String? bearerToken,
  }) async => APIResponse.success(const {});
}

/// An unlocked vault, without secure storage.
class _Vault extends VaultCubit {
  _Vault() {
    emit(
      VaultState(
        status: AuthStatus.unlocked,
        masterSeed: base64Encode(List.filled(32, 7)),
      ),
    );
  }
}

/// A port nothing listens on, so no socket is ever really open, but the
/// topics are joined and a ring can be played in. A channel in the clear, so
/// it opens at once.
final _server = Server(
  id: 'srv',
  name: 'Lighthouse',
  supabaseUrl: 'http://127.0.0.1:9/srv',
  supabaseKey: 'anon',
  token: 'token',
  tokenIssuedAt: DateTime.now(),
  user: const ServerUser(
    id: 'me',
    username: 'me',
    displayName: 'Me',
    permissions: UserPermissions(),
  ),
  channels: const [
    Channel(
      id: 't1',
      name: 't1',
      channelType: ChannelType.text,
      isEncrypted: false,
    ),
  ],
);

Future<void> _settle() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Directory cache;
  late SessionRepository session;
  late ChannelChatCubit chat;

  Future<_Reads> open(_Reads reads) async {
    session = SessionRepository(servers: reads)
      ..publish(servers: [_server], selectedServerId: _server.id);
    cache = Directory.systemTemp.createTempSync('rift_cache');
    chat = ChannelChatCubit(
      session: session,
      vaultCubit: _Vault(),
      messageCache: MessageCache(root: () async => cache),
    );
    await _settle();
    await chat.openChannel('srv', 't1');
    await _settle();
    reads.asked.clear();
    return reads;
  }

  tearDown(() async {
    await chat.close();
    await session.realtime.dispose();
    await session.dispose();
    cache.deleteSync(recursive: true);
  });

  Future<void> rung({String? by}) async {
    session.realtime.debugBroadcast(
      'srv',
      ServerTopics.server('srv'),
      ServerEvent.reaction,
      {'message_id': '5', 'channel_id': 't1', 'user_id': ?by},
    );
    await _settle();
  }

  test('a tap is one request, and its own ring asks nothing', () async {
    final reads = await open(_Reads(is067: true));
    await chat.toggleReaction('5', '👍');
    await _settle();
    expect(reads.asked, ['toggle_reaction']);

    await rung(by: 'me');
    expect(reads.asked, ['toggle_reaction']);

    // Somebody else, or another of our devices with nothing owed.
    await rung(by: 'pal');
    await rung(by: 'me');
    expect(reads.asked, [
      'toggle_reaction',
      'message_reaction_tallies',
      'message_reaction_tallies',
    ]);
  });

  test(
    'a server from before it is read after the tap and on its ring',
    () async {
      final reads = await open(_Reads(is067: false));
      await chat.toggleReaction('5', '👍');
      await _settle();
      await rung();
      expect(reads.asked, [
        'toggle_reaction',
        'message_reaction_tallies',
        'message_reaction_tallies',
      ]);
    },
  );
}
