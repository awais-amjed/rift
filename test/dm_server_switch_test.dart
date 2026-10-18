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
import 'package:rift/logic/cubits/dm/dm_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// The DM list is one cubit told which server to show, and a read it sent
/// one server can come back after it has been told another. Drawn, that read
/// listed the last server's conversations on the new one — and a quick A, B, C
/// finished setting up B behind C.

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

/// Each server's conversation list answers only when the test says so; the
/// rest answer at once, empty.
class _HeldServers extends ServerRepository {
  final Map<String, List<Completer<APIResponse>>> lists = {};

  @override
  Future<APIResponse> listDmConversations(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    int? before,
  }) {
    final answer = Completer<APIResponse>();
    (lists[supabaseUrl] ??= []).add(answer);
    return answer.future;
  }

  @override
  Future<APIResponse> dmRequests(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) async => APIResponse.success(const []);

  @override
  Future<APIResponse> listBlocks(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) async => APIResponse.success(const []);

  /// Answer every list [url] was asked for with one conversation, with
  /// somebody who is only on that server.
  void answer(String url) {
    for (final pending in lists.remove(url) ?? const <Completer>[]) {
      pending.complete(
        APIResponse.success({
          'conversations': [
            {'peer_id': 'peer@$url', 'peer_name': 'Peer'},
          ],
          'has_more': false,
        }),
      );
    }
  }
}

String _url(String id) => 'https://$id.invalid';

/// No anon key, so nothing here opens a socket; a fresh token, so nothing
/// signs in again.
Server _server(String id) => Server(
  id: id,
  name: id,
  supabaseUrl: _url(id),
  token: 'token',
  tokenIssuedAt: DateTime.now(),
  user: ServerUser(
    id: 'me@$id',
    username: 'me',
    displayName: 'Me',
    permissions: const UserPermissions(),
  ),
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  late _HeldServers servers;
  late SessionRepository session;
  late DmCubit dms;

  setUp(() {
    servers = _HeldServers();
    session = SessionRepository(servers: servers)
      ..publish(servers: [_server('a'), _server('b'), _server('c')]);
    dms = DmCubit(session: session, vaultCubit: _UnlockedVault());
  });

  tearDown(() => dms.close());

  List<String> peers() => [
    for (final conversation in dms.state.conversations) conversation.peerId,
  ];

  test('a quick A, B, C ends on C, listing only C', () async {
    dms.showServer('a');
    await _settle();
    servers.answer(_url('a'));
    await _settle();
    expect(peers(), ['peer@${_url('a')}']);

    dms.showServer('b');
    dms.showServer('c');
    await _settle();
    await _settle();
    servers.answer(_url('c'));
    await _settle();
    // B's list, if it was ever asked for, lands last.
    servers.answer(_url('b'));
    await _settle();

    expect(dms.serverId, 'c');
    expect(peers(), ['peer@${_url('c')}']);
  });

  test('a list read on the last server is dropped when it lands', () async {
    dms.showServer('a');
    await _settle();
    // A's list is still out when B is shown.
    dms.showServer('b');
    await _settle();
    await _settle();
    servers.answer(_url('b'));
    await _settle();
    servers.answer(_url('a'));
    await _settle();

    expect(dms.serverId, 'b');
    expect(peers(), ['peer@${_url('b')}']);
  });

  test('B is not listed before its own list lands', () async {
    dms.showServer('a');
    await _settle();
    dms.showServer('b');
    await _settle();
    await _settle();
    var listed = false;
    unawaited(dms.listedFor('b').then((_) => listed = true));
    servers.answer(_url('a'));
    await _settle();
    expect(listed, isFalse, reason: "A's list is not B's");
    servers.answer(_url('b'));
    await _settle();
    expect(listed, isTrue);
  });

  test('nothing shown while a switch is let go stays nothing', () async {
    dms.showServer('a');
    await _settle();
    servers.answer(_url('a'));
    await _settle();
    dms.showServer('b');
    dms.showServer(null);
    await _settle();
    await _settle();
    servers.answer(_url('b'));
    await _settle();

    expect(dms.serverId, isNull);
    expect(peers(), isEmpty);
  });
}
