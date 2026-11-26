import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/auth_status.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift/logic/services/channel_keyring.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// A channel's keyring reloaded for another channel while its first load is
/// still waiting on the server. Found in review (Nov 21): the first answer
/// landed in the second channel's ring, and when it finished last the second
/// channel was sent to under the first one's key.

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

/// `get_channel_key` per channel; a channel in [held] answers only when its
/// completer is completed.
class _KeyServers extends ServerRepository {
  final Map<String, Map<String, dynamic>> answers = {};
  final Map<String, Completer<void>> held = {};

  @override
  Future<APIResponse> getChannelKey(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
  }) async {
    await held[channelId]?.future;
    return APIResponse.success(answers[channelId]!);
  }
}

const _url = 'https://keys.invalid';

final _server = Server(
  id: 'server',
  name: 'server',
  supabaseUrl: _url,
  token: 'token',
  user: const ServerUser(
    id: 'me',
    username: 'me',
    displayName: 'Me',
    permissions: UserPermissions(),
  ),
);

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  late _KeyServers servers;
  late ChannelKeyring ring;
  late Uint8List keyA;
  late Uint8List keyB;

  setUp(() async {
    servers = _KeyServers();
    final session = SessionRepository(servers: servers)
      ..publish(servers: [_server], selectedServerId: 'server');
    final vault = _UnlockedVault();
    final crypto = CryptoRepository();
    ring = ChannelKeyring(session: session, vaultCubit: vault, crypto: crypto);

    final me = await vault.getChatIdentityForHost(
      Uri.parse(_url).host,
      version: CryptoRepository.chatIdentityVersion,
    );
    Future<Map<String, dynamic>> answer(Uint8List key, int version) async {
      final sealed = await crypto.sealKeyringEntries(
        key: key,
        members: [
          {'user_id': 'me', 'chat_public_key': me.publicKeyBase64},
        ],
      );
      return {
        'current_version': version,
        'my_keys': [
          {...sealed.single, 'key_version': version},
        ],
        'members_missing': const [],
      };
    }

    keyA = crypto.generateChannelKey();
    keyB = crypto.generateChannelKey();
    // A is further along its rotations than B, so a key of A's left in the
    // ring would also be the one a send in B picked.
    servers.answers['a'] = await answer(keyA, 3);
    servers.answers['b'] = await answer(keyB, 1);
  });

  test('a load finishing after the ring moved on writes nothing', () async {
    servers.held['a'] = Completer<void>();
    final first = ring.loadOrBootstrap('a', serverId: 'server');
    // Let the first load reach the server before the second begins.
    await pumpEventQueue();

    final second = await ring.loadOrBootstrap('b', serverId: 'server');
    expect(second.isReady, isTrue);

    servers.held['a']!.complete();
    final stale = await first;

    expect(stale.isReady, isFalse);
    expect(ring.currentVersion, 1);
    expect(ring.keys.keys, [1]);
    expect(ring.currentKey, keyB);
  });

  test('an absorb for the channel left behind adds nothing', () async {
    await ring.loadOrBootstrap('b', serverId: 'server');

    expect(await ring.absorbNewVersions('a'), isFalse);
    expect(ring.keys.keys, [1]);
    expect(ring.currentKey, keyB);
  });

  test('an absorb cleared under it adds nothing', () async {
    await ring.loadOrBootstrap('a', serverId: 'server');
    servers.held['a'] = Completer<void>();
    final absorbing = ring.absorbNewVersions('a');
    await pumpEventQueue();

    ring.clear();
    servers.held['a']!.complete();

    expect(await absorbing, isFalse);
    expect(ring.keys, isEmpty);
  });
}
