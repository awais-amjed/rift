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

/// Self-host 066: opening a channel is one `channel_open` request, not five
/// (the page, the bar, the keys, the bots holding one and the bots a `/`
/// reaches); a server from before it is asked them apart. And keys asked for
/// before this member's chat key was first published are asked again.
class _Reads extends ServerRepository {
  _Reads({required this.is066, this.newlyKeyed = false});

  final bool is066;
  final bool newlyKeyed;
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
    asked.add('channel_open');
    if (!is066) {
      return APIResponse(success: false, errorCode: 'PGRST202');
    }
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
  }) async => APIResponse.success({
    'published': true,
    publishedChatKeyIsNew: newlyKeyed,
  });

  @override
  Future<APIResponse> sweepChannelKeys(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) async => APIResponse.success(const {'work': [], 'more': false});

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

/// No anon key, so nothing here opens a socket. A channel in the clear, so
/// one with no key sealed to us yet opens at once.
final _server = Server(
  id: 'srv',
  name: 'Lighthouse',
  supabaseUrl: 'https://srv.invalid',
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
    reads.asked.clear();
    await chat.openChannel('srv', 't1');
    await _settle();
    return reads;
  }

  tearDown(() async {
    await chat.close();
    await session.dispose();
    cache.deleteSync(recursive: true);
  });

  test('a channel opens with one request', () async {
    final reads = await open(_Reads(is066: true));
    expect(reads.asked, ['channel_open']);
    expect(chat.state.status, ChannelChatStatus.ready);
  });

  test('a server from before it is asked the five apart', () async {
    final reads = await open(_Reads(is066: false));
    expect(
      reads.asked,
      unorderedEquals([
        'channel_open',
        'channel_bot_listeners',
        'list_members',
        'channel_messages',
        'my_channel_key',
        'channel_live_messages',
      ]),
    );
    expect(chat.state.status, ChannelChatStatus.ready);
  });

  test(
    'keys asked before our chat key was published are asked again',
    () async {
      final reads = await open(_Reads(is066: true, newlyKeyed: true));
      expect(reads.asked, ['channel_open', 'my_channel_key']);
    },
  );
}
