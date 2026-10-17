import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/auth_status.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift/logic/services/channel_keyring.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// A call's channel keys belong to the call's server, not to whichever server
/// the person is reading. Found in a bug report: in a call on one server, the
/// member opened another, the key rotation and heals went to that one
/// (`channel_not_found` in its log), and back in the call nobody could be
/// heard and no stream played.

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
