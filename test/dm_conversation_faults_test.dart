import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/auth_status.dart';
import 'package:rift/data/enums/error_code.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/dm/dm_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// Server DMs, from the review of Nov 21: a peer's broken chat key, a first
/// page that never came, an answer lost after the server stored a message,
/// and paging past a row whose newest message was dropped.

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

const _url = 'https://dms.invalid';
const _me = 'me';
const _peer = 'peer';
final _created = DateTime.utc(2026, 11, 21).toIso8601String();

String _bytes(int fill) =>
    CryptoRepository.toBase64(Uint8List.fromList(List.filled(32, fill)));

/// A server whose DM reads answer what each test sets.
class _DmServer extends ServerRepository {
  /// `dm_conversations`, by the `before` it was asked with.
  final Map<int?, Map<String, dynamic>> conversationPages = {};
  final List<int?> conversationCursors = [];

  /// `list_dms`: the newest page, and what comes after an id.
  APIResponse latest = APIResponse.success({
    'messages': const [],
    'has_more': false,
  });
  List<Map<String, dynamic>> after = const [];

  final List<Map<String, dynamic>> sent = [];
  APIResponse Function(Map<String, dynamic> envelope)? answerSend;

  @override
  Future<APIResponse> listDmConversations(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    int? before,
  }) async {
    conversationCursors.add(before);
    return APIResponse.success(
      conversationPages[before] ??
          {'conversations': const [], 'has_more': false},
    );
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

  @override
  Future<APIResponse> dmLinkState(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String peerId,
  }) async => APIResponse.success('open');

  @override
  Future<APIResponse> dmCallLog(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String peerId,
    DateTime? since,
  }) async => APIResponse.success(const []);

  @override
  Future<APIResponse> listDms(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String peerId,
    int? beforeId,
    int? afterId,
    int? limit,
  }) async {
    if (afterId == null) return latest;
    return APIResponse.success({
      'messages': [
        for (final row in after)
          if ((row['id'] as int) > afterId) row,
      ],
      'has_more': false,
    });
  }

  @override
  Future<APIResponse> sendDm(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String recipientId,
    required Map<String, dynamic> envelope,
  }) async {
    sent.add(envelope);
    return answerSend?.call(envelope) ??
        APIResponse.success({'id': 100 + sent.length, 'created_at': _created});
  }
}

final _server = Server(
  id: 'server',
  name: 'server',
  supabaseUrl: _url,
  token: 'token',
  tokenIssuedAt: DateTime.now(),
  user: const ServerUser(
    id: _me,
    username: 'me',
    displayName: 'Me',
    permissions: UserPermissions(),
  ),
);

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  late _DmServer server;
  late SessionRepository session;
  late DmCubit dms;

  setUp(() {
    server = _DmServer();
    session = SessionRepository(servers: server)..publish(servers: [_server]);
    dms = DmCubit(session: session, vaultCubit: _UnlockedVault());
  });

  tearDown(() => dms.close());

  Future<void> open() async {
    dms.showServer('server');
    await _settle();
    await dms.openConversation(
      peerId: _peer,
      peerName: 'Peer',
      peerChatKey: _bytes(5),
    );
    await _settle();
  }

  test('a peer whose chat key is not a key leaves the list readable', () async {
    server.conversationPages[null] = {
      'conversations': [
        {
          'peer_id': 'broken',
          'peer_name': 'Broken',
          'peer_chat_public_key': 'x',
          'peer_public_key': _bytes(1),
          'last_message': {
            'id': 9,
            'sender_id': 'broken',
            'created_at': _created,
            'ciphertext': 'AA==',
            'nonce': 'AA==',
            'signature': 'AA==',
            'key_version': 1,
          },
        },
        {'peer_id': 'fine', 'peer_name': 'Fine'},
      ],
      'has_more': false,
    };
    dms.showServer('server');
    await _settle();

    expect(dms.state.conversationsLoading, isFalse);
    expect(dms.state.conversationsFailed, isFalse);
    expect(
      [for (final c in dms.state.conversations) c.peerId],
      ['broken', 'fine'],
    );
    // Locked, the way a message waiting on a key is — not an error.
    expect(dms.state.conversations.first.lastMessage?.isLocked, isTrue);
  });

  test(
    'a first page that could not be read says so and can be retried',
    () async {
      server.latest = APIResponse.error(
        'down',
        errorCode: ErrorCode.serverUnreachable,
      );
      await open();
      expect(dms.state.chatStatus, DmChatStatus.error);
      expect(dms.state.loadFailed, isTrue);

      server.latest = APIResponse.success({
        'messages': const [],
        'has_more': false,
      });
      await dms.retryOpen();
      await _settle();
      expect(dms.state.chatStatus, DmChatStatus.ready);
      expect(dms.state.loadFailed, isFalse);
    },
  );

  test(
    'a message stored before its answer was lost is not sent twice',
    () async {
      await open();
      expect(dms.state.chatStatus, DmChatStatus.ready);
      // A send needs the server's key. Given only now, after the DMs were set
      // up without one, so no socket is opened to the invalid host.
      session.publish(servers: [_server.copyWith(supabaseKey: 'anon')]);

      server.answerSend = (_) =>
          APIResponse.error('timed out', errorCode: ErrorCode.serverTimeout);
      await dms.sendDm('hello');
      final held = dms.state.messages.single;
      expect(held.sendFailed, isTrue);

      // It was stored all the same: the server has the very envelope sent.
      final stored = server.sent.single;
      server.after = [
        {
          ...stored,
          'id': 1,
          'sender_id': _me,
          'recipient_id': _peer,
          'created_at': _created,
        },
      ];
      server.answerSend = null;
      await dms.retrySend(held.id);
      await _settle();

      expect(server.sent, hasLength(1), reason: 'read first, not sent again');
      expect([for (final m in dms.state.messages) m.id], ['1']);
      expect(dms.state.messages.single.text, 'hello');
    },
  );

  test('paging goes on past a row whose newest message was dropped', () async {
    server.conversationPages[null] = {
      'conversations': [
        {
          'peer_id': 'forged',
          'peer_name': 'Forged',
          'peer_chat_public_key': _bytes(4),
          'peer_public_key': _bytes(6),
          // Its signature fails, so it is dropped: no preview to page from.
          'last_message': {
            'id': 50,
            'sender_id': 'forged',
            'created_at': _created,
            'ciphertext': 'AA==',
            'nonce': 'AAAAAAAAAAAAAAAA',
            'signature': 'AA==',
            'key_version': 1,
          },
        },
      ],
      'has_more': true,
    };
    server.conversationPages[50] = {
      'conversations': [
        {'peer_id': 'older', 'peer_name': 'Older'},
      ],
      'has_more': false,
    };
    dms.showServer('server');
    await _settle();
    expect(dms.state.conversations.single.lastMessage, isNull);

    await dms.loadMoreConversations();
    await _settle();
    expect(server.conversationCursors.last, 50);
    expect(
      [for (final c in dms.state.conversations) c.peerId],
      ['forged', 'older'],
    );
  });
}
