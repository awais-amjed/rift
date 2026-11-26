import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/call_panels/call_panels_cubit.dart';
import 'package:rift/logic/services/server_topics.dart';

/// Self-host 065: a call's bar is one `call_panels` read, not one read per
/// text channel and one for the call; a server from before it is asked the
/// old way. And only a bot's message has the bar read again: nobody else
/// draws a panel.
class _Reads extends ServerRepository {
  _Reads({required this.is065});

  final bool is065;
  final List<String> asked = [];

  static final _empty = APIResponse.success({'messages': <dynamic>[]});

  @override
  Future<APIResponse> listCallPanels(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String callId,
  }) async {
    asked.add('call_panels');
    return is065 ? _empty : APIResponse(success: false, errorCode: 'PGRST202');
  }

  @override
  Future<APIResponse> listCallLiveMessages(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String callId,
  }) async {
    asked.add('call_live_messages');
    return _empty;
  }

  @override
  Future<APIResponse> listLiveMessages(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String channelId,
  }) async {
    asked.add('channel_live_messages $channelId');
    return _empty;
  }
}

// A port nothing listens on, so no socket is ever really open; a fresh token,
// so nothing signs in again.
final _server = Server(
  id: 'a',
  name: 'a',
  supabaseUrl: 'http://127.0.0.1:9/a',
  supabaseKey: 'anon',
  token: 'token',
  tokenIssuedAt: DateTime.now(),
  user: ServerUser(
    id: 'me',
    username: 'me',
    displayName: 'Me',
    permissions: const UserPermissions(),
  ),
  channels: const [
    Channel(id: 't1', name: 't1', channelType: ChannelType.text),
    Channel(id: 't2', name: 't2', channelType: ChannelType.text),
    Channel(id: 'v', name: 'v', channelType: ChannelType.voice),
  ],
);

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Reads reads;
  late SessionRepository session;
  late CallPanelsCubit panels;

  Future<void> start({required bool is065}) async {
    reads = _Reads(is065: is065);
    session = SessionRepository(servers: reads)..publish(servers: [_server]);
    panels = CallPanelsCubit(session: session, serverId: 'a')
      ..watchBots(const Stream.empty(), initial: {'bot'})
      ..watchCall(
        const Stream.empty(),
        initial: (channelId: 'v', userIds: {'me', 'pal', 'bot'}),
      );
    await _settle();
  }

  tearDown(() async {
    await panels.close();
    await session.realtime.dispose();
  });

  void posted(String sender) => session.realtime.debugBroadcast(
    'a',
    ServerTopics.server('a'),
    ServerEvent.message,
    {'channel_id': 't1', 'sender_id': sender},
  );

  test('a call starts with one read of its whole bar', () async {
    await start(is065: true);
    expect(reads.asked, ['call_panels']);

    // Somebody in the call posting draws no panel; a bot posting may.
    reads.asked.clear();
    posted('pal');
    await _settle();
    expect(reads.asked, isEmpty);
    posted('bot');
    await _settle();
    expect(reads.asked, ['call_panels']);
  });

  test('a server from before it is read call and channels apart', () async {
    await start(is065: false);
    expect(
      reads.asked,
      unorderedEquals([
        'call_panels',
        'call_live_messages',
        'channel_live_messages t1',
        'channel_live_messages t2',
      ]),
    );

    reads.asked.clear();
    posted('bot');
    await _settle();
    expect(
      reads.asked,
      unorderedEquals([
        'call_panels',
        'channel_live_messages t1',
        'call_live_messages',
      ]),
    );
  });
}
