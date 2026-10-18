import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/dm_call_place.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/auth_status.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/server_session.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift/logic/services/channel_keyring.dart';
import 'package:rift/logic/services/server_context.dart';
import 'package:rift/logic/services/server_hub.dart';
import 'package:rift/presentation/common/server_context_scope.dart';
import 'package:rift/presentation/common/server_scope.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// A call's channel keys belong to the call's server, not to whichever server
/// the person is reading. Found in a bug report: in a call on one server, the
/// member opened another, the key rotation and heals went to that one
/// (`channel_not_found` in its log), and back in the call nobody could be
/// heard and no stream played.
///
/// And everything else the call draws and does, found the day after: opening
/// another server mid-call swapped every face in the call for a generated
/// one, because the tiles read the selected server's roster.

/// In-memory stand-in for the hydrated cubits the vault touches.
class _MemoryStorage implements Storage {
  final Map<String, dynamic> _data = {};

  @override
  dynamic read(String key) => _data[key];

  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> close() async {}
}

/// A vault already unlocked with a fixed seed.
class _UnlockedVault extends VaultCubit {
  _UnlockedVault() {
    emit(
      VaultState(
        status: AuthStatus.unlocked,
        masterSeed: CryptoRepository.toBase64(
          Uint8List.fromList(List.filled(32, 7)),
        ),
      ),
    );
  }
}

/// Every key call answered, and the server each one reached written down.
class _RecordingServers extends ServerRepository {
  final List<(String call, String url)> calls = [];

  /// What `get_channel_key` answers.
  Map<String, dynamic> channelKey = const {};

  @override
  Future<APIResponse> getChannelKey(
    String supabaseUrl, {
    String? bearerToken,
    required String channelId,
  }) async {
    calls.add(('get', supabaseUrl));
    return APIResponse.success(channelKey);
  }

  @override
  Future<APIResponse> postChannelKeys(
    String supabaseUrl, {
    String? bearerToken,
    required String channelId,
    required int keyVersion,
    required List<Map<String, dynamic>> entries,
    required bool mint,
    ({String ciphertext, String nonce})? link,
  }) async {
    calls.add(('post', supabaseUrl));
    return APIResponse.success(const {});
  }

  @override
  Future<APIResponse> postBotVoiceKey(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
    required String botId,
    required int keyVersion,
    required bool isChannelKey,
    required Map<String, dynamic> wrapped,
    required String wrappedBy,
  }) async {
    calls.add(('bot', supabaseUrl));
    return APIResponse.success(const {});
  }
}

const _callUrl = 'https://call.invalid';
const _otherUrl = 'https://other.invalid';
const _voiceId = 'voice-1';

Server _server(String id, String url, {List<Channel> channels = const []}) =>
    Server(
      id: id,
      name: id,
      supabaseUrl: url,
      token: 'token',
      user: const ServerUser(
        id: 'me',
        username: 'me',
        displayName: 'Me',
        permissions: UserPermissions(),
      ),
      channels: channels,
    );

final _callServer = _server(
  'call',
  _callUrl,
  channels: const [
    Channel(id: _voiceId, name: 'Voice', channelType: ChannelType.voice),
  ],
);
final _otherServer = _server('other', _otherUrl);

/// A server's context with nothing live in it: what [ServerHub] keeps and
/// shuts, and the one roster a scope test reads.
class _FakeContext implements ServerContext {
  @override
  final String serverId;
  @override
  final ServerSession session;
  final ServerMembersCubit? _members;
  final void Function(String serverId)? onClose;

  _FakeContext(
    SessionRepository session,
    this.serverId, {
    ServerMembersCubit? members,
    this.onClose,
  }) : session = session.on(serverId),
       _members = members;

  @override
  ServerMembersCubit get members => _members!;

  @override
  Widget provide(Widget child) => _members == null
      ? child
      : BlocProvider<ServerMembersCubit>.value(value: _members, child: child);

  @override
  Future<void> close() async => onClose?.call(serverId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  group('SessionRepository.serverWithChannel', () {
    test('finds the channel on a server that is not selected', () {
      final session = SessionRepository()
        ..publish(
          servers: [_callServer, _otherServer],
          selectedServerId: 'other',
        );
      expect(session.serverWithChannel(_voiceId)?.id, 'call');
      expect(session.serverWithChannel('nowhere'), isNull);
    });
  });

  group('a call keyring', () {
    late _RecordingServers servers;
    late SessionRepository session;
    late ChannelKeyring ring;

    setUp(() async {
      servers = _RecordingServers();
      session = SessionRepository(servers: servers)
        ..publish(
          servers: [_callServer, _otherServer],
          selectedServerId: 'call',
        );
      final vault = _UnlockedVault();
      final crypto = CryptoRepository();
      ring = ChannelKeyring(
        session: session,
        vaultCubit: vault,
        crypto: crypto,
      );

      // Version 1 sealed to us, a member and a bot still short of it.
      final me = await vault.getChatIdentityForHost(
        Uri.parse(_callUrl).host,
        version: CryptoRepository.chatIdentityVersion,
      );
      final otherKey = (await crypto.deriveChatIdentity(
        masterSeed: Uint8List.fromList(List.filled(32, 9)),
        host: Uri.parse(_callUrl).host,
      )).publicKeyBase64;
      final sealed = await crypto.sealKeyringEntries(
        key: crypto.generateChannelKey(),
        members: [
          {'user_id': 'me', 'chat_public_key': me.publicKeyBase64},
        ],
      );
      servers.channelKey = {
        'current_version': 1,
        'my_keys': [
          {...sealed.single, 'key_version': 1},
        ],
        'members_missing': [
          {'user_id': 'them', 'chat_public_key': otherKey},
        ],
        'bots_missing': [
          {'bot_id': 'bot', 'chat_public_key': otherKey, 'may_listen': false},
        ],
        'links': const [],
      };
    });

    /// Lets the fire-and-forget heals and seals finish.
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('loads, heals and seals on the server it was asked for', () async {
      session.publish(
        servers: [_callServer, _otherServer],
        selectedServerId: 'other',
      );

      final outcome = await ring.loadOrBootstrap(_voiceId, serverId: 'call');
      await settle();

      expect(outcome.isReady, isTrue);
      expect(servers.calls.map((c) => c.$1), containsAll(['get', 'post']));
      expect(servers.calls.map((c) => c.$2).toSet(), {_callUrl});
    });

    test('keeps to that server after the selection moves', () async {
      await ring.loadOrBootstrap(_voiceId, serverId: 'call');
      await settle();
      servers.calls.clear();

      session.publish(
        servers: [_callServer, _otherServer],
        selectedServerId: 'other',
      );
      // What the call does on the doorbell: take a rotation, then seal any
      // bot short of a key.
      await ring.absorbNewVersions(_voiceId);
      await ring.sealMissingBotKeys(_voiceId);
      await ring.healMembers(
        _voiceId,
        1,
        (servers.channelKey['members_missing'] as List)
            .cast<Map<String, dynamic>>(),
      );
      await settle();

      expect(
        servers.calls.map((c) => c.$1),
        containsAll(['get', 'bot', 'post']),
      );
      expect(servers.calls.map((c) => c.$2).toSet(), {_callUrl});
    });
  });

  group('the call\'s server', () {
    // Old enough that a watcher holds off joining, so nothing here opens a
    // socket.
    final stale = DateTime(2000);
    Server signedIn(String id, String url) => Server(
      id: id,
      name: id,
      supabaseUrl: url,
      supabaseKey: 'key',
      token: 'token',
      tokenIssuedAt: stale,
      user: const ServerUser(
        id: 'me',
        username: 'me',
        displayName: 'Me',
        permissions: UserPermissions(),
      ),
    );

    test(
      'the session says where the call is, and only when it moves',
      () async {
        final session = SessionRepository()
          ..publish(
            servers: [_callServer, _otherServer],
            selectedServerId: 'other',
          );
        var moves = 0;
        final sub = session.callChanges.listen((_) => moves++);

        session.publishCall('call');
        session.publishCall('call');
        await Future<void>.delayed(Duration.zero);
        expect(session.callServer?.id, 'call');
        expect(session.selectedServer?.id, 'other');
        expect(moves, 1);

        session.publishCall(null);
        await Future<void>.delayed(Duration.zero);
        expect(session.callServer, isNull);
        expect(moves, 2);
        await sub.cancel();
      },
    );

    test('the hub holds the call\'s server while another is read', () async {
      final session = SessionRepository()
        ..publish(
          servers: [signedIn('call', _callUrl), signedIn('other', _otherUrl)],
          selectedServerId: 'call',
        );
      final opened = <String>[];
      final closed = <String>[];
      final hub = ServerHub(
        session: session,
        open: (id) {
          opened.add(id);
          return _FakeContext(session, id, onClose: closed.add);
        },
      );
      expect(opened, ['call']);

      session.publishCall('call');
      await Future<void>.delayed(Duration.zero);
      session.publish(servers: session.servers, selectedServerId: 'other');
      await Future<void>.delayed(Duration.zero);
      expect(opened, ['call', 'other']);
      expect(closed, isEmpty, reason: 'the call still holds its server');
      expect(hub['call'], isNotNull);

      session.publishCall(null);
      await Future<void>.delayed(Duration.zero);
      expect(closed, ['call'], reason: 'nothing holds it once the call ends');
      expect(hub['call'], isNull);
      expect(hub['other']?.serverId, 'other');
      await hub.dispose();
      expect(closed, ['call', 'other']);
    });

    test('a server nothing holds is shut at once, and shared while held', () {
      final session = SessionRepository()
        ..publish(servers: [signedIn('call', _callUrl)]);
      final closed = <String>[];
      final hub = ServerHub(
        session: session,
        open: (id) => _FakeContext(session, id, onClose: closed.add),
      );
      final page = hub.hold('call');
      final menu = hub.hold('call');
      expect(menu.context, same(page.context));

      page.release();
      page.release();
      expect(closed, isEmpty, reason: 'a hold is let go once');
      menu.release();
      expect(closed, ['call']);
      expect(hub['call'], isNull);

      // What the screen reads with nothing selected: never held, never shut.
      expect(hub.none.serverId, isEmpty);
      expect(hub[''], isNull);
      expect(closed, ['call']);
    });

    test('a call\'s channel is found on whichever server has it', () {
      final state = ServerState(
        servers: [_otherServer, _callServer],
        selectedServerId: 'other',
      );
      expect(state.serverWithChannel(_voiceId)?.id, 'call');
      expect(state.serverWithChannel('nowhere'), isNull);
    });

    test(
      'a DM call is on its own server, a channel call on its channel\'s',
      () {
        const inChannel = LiveKitState(
          currentChannelId: _voiceId,
          currentServerId: 'call',
        );
        expect(inChannel.callServerId, 'call');
        expect(const LiveKitState().callServerId, isNull);
        final dm = LiveKitState(
          dmCall: DmCallPlace(
            serverId: 'other',
            callId: 'c1',
            peerId: 'them',
            peerName: 'Them',
          ),
        );
        expect(dm.callServerId, 'other');
      },
    );
  });

  group('ServerScope', () {
    testWidgets('a menu built outside the call takes its server along', (
      tester,
    ) async {
      final session = SessionRepository()
        ..publish(servers: [_callServer, _otherServer]);
      final callMembers = ServerMembersCubit(
        session: session,
        serverId: 'call',
      );
      addTearDown(callMembers.close);
      final hub = ServerHub(
        session: session,
        open: (id) => _FakeContext(session, id, members: callMembers),
      );
      addTearDown(hub.dispose);
      late BuildContext inside;
      await tester.pumpWidget(
        RepositoryProvider.value(
          value: hub,
          child: ServerContextScope(
            serverId: 'call',
            child: Builder(
              builder: (context) {
                inside = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // What a menu, a sheet or a route does: build from that context
      // somewhere else entirely.
      ServerSession? scoped;
      ServerMembersCubit? roster;
      final carry = ServerScope.carrier(inside);
      await tester.pumpWidget(
        RepositoryProvider.value(
          value: hub,
          child: carry(
            Builder(
              builder: (context) {
                scoped = ServerScope.of(context);
                roster = context.read<ServerMembersCubit>();
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(scoped?.serverId, 'call');
      expect(roster, same(callMembers));
      expect(hub['call'], isNotNull, reason: 'the menu holds it open');
    });

    testWidgets('outside a scope nothing is carried', (tester) async {
      late BuildContext outside;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            outside = context;
            return const SizedBox();
          },
        ),
      );
      const child = SizedBox();
      expect(ServerScope.carry(outside, child), same(child));
    });
  });

  group('LiveKitState', () {
    test('the call\'s server goes with its channel', () {
      const state = LiveKitState(
        currentChannelId: _voiceId,
        currentServerId: 'call',
      );
      expect(state.copyWith(clearChannelId: true).currentServerId, isNull);
      expect(
        state
            .copyWith(currentChannelId: 'elsewhere', clearServerId: true)
            .currentServerId,
        isNull,
      );
      expect(
        state.copyWith(currentChannelId: 'elsewhere').currentServerId,
        'call',
      );
    });
  });
}
