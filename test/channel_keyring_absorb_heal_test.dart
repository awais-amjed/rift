import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/sealed_keys.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/auth_status.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift/logic/services/channel_keyring.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// A keyring absorbing new versions heals the members its answer lists as
/// missing. The read (`my_channel_key`) takes the channel's lease for whoever
/// asked, so the other members' sweeps leave the channel alone; found live on
/// Nov 27, an unban healed the member back in every channel but the one a
/// client had open and the one it was in a call in, for as long as it stayed.

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

/// One answer for `get_channel_key`, and every heal written kept.
class _KeyServer extends ServerRepository {
  late Map<String, dynamic> answer;
  final List<SealedKeys> written = [];

  @override
  Future<APIResponse> getChannelKey(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
  }) async => APIResponse.success(answer);

  @override
  Future<APIResponse> postChannelKeys(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required SealedKeys keys,
  }) async {
    written.add(keys);
    return APIResponse.success(const {});
  }
}

const _url = 'https://keys.invalid';

/// A heal runs unawaited, and sealing takes real time: wait for [done], up to
/// a second.
Future<void> _settled(bool Function() done) async {
  for (var i = 0; i < 50 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

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

  late _KeyServer server;
  late ChannelKeyring ring;
  late CryptoRepository crypto;
  late Map<String, dynamic> mine;
  late Map<String, dynamic> missing;
  final healed = <String>[];

  setUp(() async {
    healed.clear();
    server = _KeyServer();
    final session = SessionRepository(servers: server)
      ..publish(servers: [_server], selectedServerId: 'server');
    final vault = _UnlockedVault();
    crypto = CryptoRepository();
    ring = ChannelKeyring(
      session: session,
      vaultCubit: vault,
      crypto: crypto,
      onHealed: healed.add,
    );

    final me = await vault.getChatIdentityForHost(
      Uri.parse(_url).host,
      version: CryptoRepository.chatIdentityVersion,
    );
    final key = crypto.generateChannelKey();
    final sealed = await crypto.sealKeyringEntries(
      key: key,
      members: [
        {'user_id': 'me', 'chat_public_key': me.publicKeyBase64},
      ],
    );
    mine = {...sealed.single, 'key_version': 2};
    // Any key seals; whose it is does not matter here.
    missing = {'user_id': 'other', 'chat_public_key': me.publicKeyBase64};
    // Loaded with nobody missing, as a member opening the channel.
    server.answer = {
      'current_version': 2,
      'my_keys': [mine],
      'members_missing': const [],
    };
    await ring.loadOrBootstrap('c', serverId: 'server');
  });

  test('heals the members the answer lists, at the version it holds', () async {
    server.answer = {
      'current_version': 2,
      'my_keys': [mine],
      'members_missing': [missing],
    };

    await ring.absorbNewVersions('c');
    await _settled(() => server.written.isNotEmpty && healed.isNotEmpty);

    expect(server.written, hasLength(1));
    final heal = server.written.single;
    expect(heal.channelId, 'c');
    expect(heal.keyVersion, 2);
    expect(heal.mint, isFalse);
    expect(heal.entries.map((e) => e['user_id']), ['other']);
    expect(healed, ['c']);
  });

  test('heals nobody with a version it was not sealed', () async {
    server.answer = {
      'current_version': 3,
      'my_keys': [mine],
      'members_missing': [missing],
    };

    await ring.absorbNewVersions('c');
    await _settled(() => server.written.isNotEmpty);

    expect(ring.currentVersion, 2);
    expect(server.written, isEmpty);
  });
}
