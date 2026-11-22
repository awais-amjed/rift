import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rift/data/repositories/secure_storage_repository.dart';
import 'package:rift/data/repositories/server_pass_repository.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// A pass from central names one server by its address and carries the tag
/// that server keeps for the account, readable by whoever holds the pass. A
/// server's `resolve_invite` names its own address, and a dishonest one could
/// name another's: the app then asked central for a pass naming that other
/// server and handed it to the dishonest one, which learnt the other server's
/// tag for the account (found in the Nov 16 2026 security review). So a pass
/// goes only to the address it names, and the whole join goes there with it.
void main() {
  const code = 'abc';
  const serverId = '11111111-1111-4111-8111-111111111111';
  const otherId = '22222222-2222-4222-8222-222222222222';

  late _Servers servers;
  late _Passes passes;
  late _Storage storage;
  late _Vault vault;

  setUp(() async {
    servers = _Servers();
    passes = _Passes();
    storage = _Storage();
    vault = _Vault(
      storage: storage,
      serverRepo: ServerRepository(client: servers.client),
      passRepo: passes,
    );
    await vault.checkVaultStatus();
  });

  tearDown(() => vault.close());

  Future<({bool success, String? error, String? serverUrl})> join(
    String link,
  ) async {
    final result = await vault.registerOnServer(
      supabaseUrl: link,
      inviteCode: code,
      username: 'cara',
      displayName: 'Cara',
    );
    return (
      success: result.success,
      error: result.error,
      serverUrl: result.serverUrl,
    );
  }

  test('a marked link reaching the server another way joins at the address '
      'the pass names', () async {
    servers.invite['http://192.168.1.6:8000'] = {
      'server_id': serverId,
      'needs_account': true,
      'public_url': 'https://rift.example',
    };
    servers.invite['https://rift.example'] = {
      'server_id': serverId,
      'needs_account': true,
      'public_url': 'https://rift.example',
    };

    final result = await join('http://192.168.1.6:8000');

    expect(result.success, isTrue, reason: result.error);
    expect(passes.askedFor, ['https://rift.example']);
    expect(vault.signedInAt, ['https://rift.example']);
    expect(servers.registers, [
      ('https://rift.example', 'pass:https://rift.example'),
    ]);
    expect(result.serverUrl, 'https://rift.example');
    expect(storage.joinedHosts, ['rift.example']);
  });

  test("a server naming another's address gets no pass", () async {
    // The other server does not know this server's invite.
    servers.invite['https://m.example'] = {
      'server_id': serverId,
      'needs_account': true,
      'public_url': 'https://v.example',
    };

    final result = await join('https://m.example');

    expect(result.success, isFalse);
    expect(passes.askedFor, isEmpty);
    expect(servers.registers, isEmpty);
  });

  test('a different server at the address given is not joined', () async {
    servers.invite['https://m.example'] = {
      'server_id': serverId,
      'needs_account': true,
      'public_url': 'https://v.example',
    };
    servers.invite['https://v.example'] = {
      'server_id': otherId,
      'needs_account': true,
      'public_url': 'https://v.example',
    };

    final result = await join('https://m.example');

    expect(result.success, isFalse);
    expect(passes.askedFor, isEmpty);
    expect(servers.registers, isEmpty);
  });

  test('a server whose register names another server is not joined', () async {
    // Its invite resolved to one id, which the key was derived for; the
    // reply claims another — one this person may hold already, whose row it
    // would be listed as.
    servers.invite['https://rift.example'] = {'server_id': serverId};
    servers.answersAs['https://rift.example'] = otherId;

    final result = await join('https://rift.example');

    expect(result.success, isFalse);
    expect(result.error, 'The server answered as a different server.');
  });

  test('a marked link at the address the server gives joins there', () async {
    servers.invite['https://rift.example'] = {
      'server_id': serverId,
      'needs_account': true,
      'public_url': 'https://rift.example',
    };

    final result = await join('https://rift.example');

    expect(result.success, isTrue, reason: result.error);
    expect(passes.askedFor, ['https://rift.example']);
    expect(servers.registers, [
      ('https://rift.example', 'pass:https://rift.example'),
    ]);
    expect(result.serverUrl, 'https://rift.example');
  });

  test(
    'a link that needs no account joins where it points, with no pass',
    () async {
      servers.invite['http://192.168.1.6:8000'] = {
        'server_id': serverId,
        'public_url': 'https://rift.example',
      };

      final result = await join('http://192.168.1.6:8000');

      expect(result.success, isTrue, reason: result.error);
      expect(passes.askedFor, isEmpty);
      expect(servers.registers, [('http://192.168.1.6:8000', null)]);
      expect(result.serverUrl, 'http://192.168.1.6:8000');
    },
  );

  // Somebody who joined at the link's address and left still has their
  // profile there, and the server lets them back without a pass: joined at
  // the server's own address, they would be a new identity and a new member.
  group('a marked link reaching the server another way, to somebody who '
      "joined at the link's address before", () {
    const link = 'http://192.168.1.6:8000';
    const own = 'https://rift.example';

    setUp(() {
      for (final origin in [link, own]) {
        servers.invite[origin] = {
          'server_id': serverId,
          'needs_account': true,
          'public_url': own,
        };
      }
      storage.joinedHosts.add('192.168.1.6');
    });

    test(
      'a former member gets their profile back there, with no pass',
      () async {
        servers.members.add(link);

        final result = await join(link);

        expect(result.success, isTrue, reason: result.error);
        expect(passes.askedFor, isEmpty);
        expect(vault.signedInAt, [link]);
        expect(servers.registers, [(link, null)]);
        expect(result.serverUrl, link);
      },
    );

    test(
      "somebody new to this server goes on to the server's own address",
      () async {
        // Joined another server on the same host, so the host is known.
        final result = await join(link);

        expect(result.success, isTrue, reason: result.error);
        expect(passes.askedFor, [own]);
        expect(servers.registers, [(link, null), (own, 'pass:$own')]);
        expect(result.serverUrl, own);
      },
    );

    test('a former member refused for anything else hears it, and nothing '
        'moves', () async {
      servers.members.add(link);
      servers.banned.add(link);

      final result = await join(link);

      expect(result.success, isFalse);
      expect(result.error, 'You are banned from this server');
      expect(passes.askedFor, isEmpty);
      expect(servers.registers, [(link, null)]);
    });
  });
}

/// Servers by address: what each one's `resolve_invite` answers for the
/// invite, and the pass each one's `register` was handed.
class _Servers {
  final Map<String, Map<String, Object?>> invite = {};
  final List<(String, String?)> registers = [];

  /// The server id each address's `register` names, when not its invite's.
  final Map<String, String> answersAs = {};

  /// Where this person already has a profile, and where they are banned.
  final Set<String> members = {};
  final Set<String> banned = {};

  late final http.Client client = MockClient((request) async {
    final origin = request.url.origin;
    final function = request.url.pathSegments.last;
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    Map<String, Object?> answer;
    switch (function) {
      case 'resolve_invite':
        final known = invite[origin];
        answer = known == null
            ? {'success': false, 'error': 'Invalid invite'}
            : {
                'success': true,
                'data': {'server_name': 'S', ...known},
              };
      case 'register':
        // As register_user answers: anybody with a profile comes back
        // without a pass, before a link's need for an account is asked.
        final pass = body['pass'] as String?;
        registers.add((origin, pass));
        final needsAccount = invite[origin]?['needs_account'] == true;
        if (banned.contains(origin)) {
          answer = {
            'success': false,
            'error': 'You are banned from this server',
            'code': 'user_banned',
          };
        } else if (!members.contains(origin) && needsAccount && pass == null) {
          answer = {
            'success': false,
            'error': 'This link needs a Rift account.',
            'code': 'account_required',
          };
        } else {
          answer = {
            'success': true,
            'data': {
              // As fetchServerContext answers: the server it signed us in to,
              // unless this one is told to answer as another.
              'server_id': answersAs[origin] ?? invite[origin]?['server_id'],
              'user': <String, Object?>{},
              'rejoined': members.contains(origin),
            },
          };
        }
      default:
        answer = {'success': false, 'error': 'unexpected $function'};
    }
    return http.Response(jsonEncode(answer), 200);
  });
}

/// Central, signed in: a pass for whichever address it is asked about.
class _Passes extends ServerPassRepository {
  final List<String> askedFor = [];

  @override
  bool get hasAccount => true;

  @override
  Future<({String? pass, String? error})> passFor({
    required String supabaseUrl,
    required String serverId,
    required String publicKey,
  }) async {
    askedFor.add(supabaseUrl);
    return (pass: 'pass:$supabaseUrl', error: null);
  }
}

class _Storage extends SecureStorageRepository {
  final List<String> joinedHosts = [];

  @override
  Future<void> finishInterruptedReplace() async {}

  @override
  Future<String?> getMasterSeed() async =>
      CryptoRepository.toBase64(Uint8List(32));

  @override
  Future<String?> getPendingRecoveryKey() async => null;

  @override
  Future<void> addJoinedServer(String host, String version) async {
    if (!joinedHosts.contains(host)) joinedHosts.add(host);
  }

  @override
  Future<List<({String url, String version})>> getJoinedServers() async => [
    for (final host in joinedHosts) (url: host, version: 'v1'),
  ];

  @override
  Future<void> saveEncryptedVault(dynamic vault) async {}
}

/// The vault, with the server sign-in answered here: where it signed in is
/// what the test is about, not how.
class _Vault extends VaultCubit {
  _Vault({super.storage, super.serverRepo, super.passRepo});

  final List<String> signedInAt = [];

  @override
  Future<({String? accessToken, String? error})> siwsLogin(
    String supabaseUrl, {
    required String serverId,
  }) async {
    signedInAt.add(supabaseUrl);
    return (accessToken: 'token', error: null);
  }
}
