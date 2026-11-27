import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/enums/auth_status.dart';
import 'package:rift/data/enums/error_code.dart';
import 'package:rift/data/enums/friendship_state.dart';
import 'package:rift/data/repositories/central_dm_repository.dart';
import 'package:rift/data/repositories/supabase_backup_repository.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/central_dm/central_dm_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift/supabase_config.dart';
import 'package:rift_crypto/rift_crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        AuthState,
        RealtimeChannel,
        RealtimeClient,
        RealtimeSubscribeStatus,
        User;

/// Rift DMs, from the review of Nov 21: a device signing in with another
/// vault, a first page that never came, an answer lost after central stored
/// a message, where the open peer stands after the graph changes, and a
/// dropped connection coming back.

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

String _seed(int fill) =>
    CryptoRepository.toBase64(Uint8List.fromList(List.filled(32, fill)));

class _UnlockedVault extends VaultCubit {
  _UnlockedVault() {
    emit(VaultState(status: AuthStatus.unlocked, masterSeed: _seed(7)));
  }
}

const _me = 'me';
const _peer = 'peer';
final _created = DateTime.utc(2026, 11, 21).toIso8601String();
String get _host => Uri.parse(SupabaseConfig.supabaseUrl).host;

/// Central, answering what each test sets.
class _Central extends CentralDmRepository {
  // Nothing signs in or out here: the session is there from the start.
  // ignore: close_sinks
  final _auth = StreamController<AuthState>.broadcast();

  /// The account's directory row, or null for none.
  Map<String, dynamic>? profile;
  final List<String> publishedChatKeys = [];

  APIResponse latest = APIResponse.success({
    'messages': const [],
    'has_more': false,
  });
  List<Map<String, dynamic>> after = const [];
  int latestReads = 0;
  int afterReads = 0;

  final List<Map<String, dynamic>> sent = [];
  APIResponse Function(Map<String, dynamic> envelope)? answerSend;

  FriendshipState? standing = FriendshipState.friends;
  int standingReads = 0;
  int countReads = 0;

  /// The conversation list's rows, and the reads of it: whole pages, and
  /// one peer's row.
  List<Map<String, dynamic>> rows = const [];
  int pageReads = 0;
  int rowReads = 0;

  /// This device's auth session, as a graph ring would name it.
  String? session = 'this-device';

  int joins = 0;
  void Function(RealtimeSubscribeStatus status)? joined;
  void Function(String senderId)? rang;
  void Function(String? session)? graph;

  @override
  String? get currentSessionId => session;

  @override
  User? get currentUser => const User(
    id: _me,
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '',
  );

  @override
  Stream<AuthState> get authChanges => _auth.stream;

  @override
  Future<APIResponse> getMyProfile() async => APIResponse.success(profile);

  @override
  Future<APIResponse> upsertProfile({
    required String handle,
    required String chatPublicKey,
    required String signingPublicKey,
  }) async {
    publishedChatKeys.add(chatPublicKey);
    profile = {
      'handle': handle,
      'chat_public_key': chatPublicKey,
      'signing_public_key': signingPublicKey,
    };
    return APIResponse.success(null);
  }

  @override
  Future<APIResponse> friendCounts() async {
    countReads++;
    return APIResponse.success((
      friends: 0,
      incoming: 0,
      outgoing: 0,
      blocked: 0,
    ));
  }

  @override
  Future<FriendshipState?> friendshipState(String peerId) async {
    standingReads++;
    return standing;
  }

  @override
  Future<APIResponse> listConversations({
    int limit = 30,
    int? before,
    String? peer,
  }) async {
    if (peer == null) {
      pageReads++;
    } else {
      rowReads++;
    }
    return APIResponse.success({
      'conversations': [
        for (final row in rows)
          if (peer == null || row['peer_id'] == peer) row,
      ],
      'has_more': false,
    });
  }

  @override
  Future<APIResponse> getQuota() async =>
      APIResponse.success({'quota': 50, 'remaining': 50});

  @override
  Future<APIResponse> listDms({
    required String peerId,
    int? beforeId,
    int? afterId,
    int limit = 50,
  }) async {
    if (afterId == null) {
      latestReads++;
      return latest;
    }
    afterReads++;
    return APIResponse.success({
      'messages': [
        for (final row in after)
          if ((row['id'] as int) > afterId) row,
      ],
      'has_more': false,
    });
  }

  @override
  Future<APIResponse> sendDm({
    required String recipientId,
    required Map<String, dynamic> envelope,
  }) async {
    sent.add(envelope);
    return answerSend?.call(envelope) ??
        APIResponse.success({
          'id': 100 + sent.length,
          'created_at': _created,
          'state': 'friends',
        });
  }

  @override
  Future<APIResponse> setReadCursor({
    required String peerId,
    required int lastReadId,
  }) async => APIResponse.success(null);

  @override
  RealtimeChannel subscribeIncoming(
    void Function(String senderId) onInsert, {
    required void Function(String messageId, String senderId) onUpdate,
    required void Function() onPrefsChanged,
    required void Function(String? peerId) onRead,
    required void Function(String? session) onGraphChanged,
    required void Function(String peerId, String messageId) onPinChanged,
    void Function(RealtimeSubscribeStatus status)? onStatus,
  }) {
    joins++;
    joined = onStatus;
    rang = onInsert;
    graph = onGraphChanged;
    return RealtimeChannel('user:$_me', RealtimeClient('ws://dms.invalid'));
  }

  @override
  Future<void> unsubscribe(RealtimeChannel channel) async {}
}

/// The account's cloud backup: [backup] as stored, or null for none.
class _Backups extends SupabaseBackupRepository {
  String? backup;

  @override
  Future<APIResponse> downloadBackup() async => APIResponse.success(backup);
}

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  late _Central central;
  late _Backups backups;
  late VaultCubit vault;
  late CentralDmCubit dms;

  /// The row this vault's own keys would publish.
  Future<Map<String, dynamic>> ownRow() async => {
    'handle': 'me',
    'chat_public_key': (await vault.getChatIdentityForHost(
      _host,
    )).publicKeyBase64,
    'signing_public_key': (await vault.getIdentityForHost(
      _host,
    )).publicKeyBase64,
  };

  Future<void> start() async {
    dms = CentralDmCubit(
      vaultCubit: vault,
      appCubit: AppCubit(),
      repo: central,
      backups: backups,
      rejoinSpread: Duration.zero,
    );
    await _settle();
  }

  setUp(() async {
    central = _Central();
    backups = _Backups();
    vault = _UnlockedVault();
    central.profile = await ownRow();
  });

  tearDown(() => dms.close());

  Future<void> open() async {
    await dms.openConversation(
      peerId: _peer,
      peerHandle: 'peer',
      peerChatKey: _seed(5),
      peerSigningKey: _seed(6),
    );
    await _settle();
  }

  group('another vault', () {
    test('publishes nothing while the account backs up another one', () async {
      central.profile = {
        'handle': 'me',
        'chat_public_key': _seed(1),
        'signing_public_key': _seed(2),
      };
      backups.backup = '{"not": "this vault"}';
      await start();

      expect(dms.state.status, CentralDmStatus.otherVault);
      expect(central.publishedChatKeys, isEmpty);
      expect(central.joins, 0);
    });

    test('publishes once the account has no backup but this one', () async {
      central.profile = {
        'handle': 'me',
        'chat_public_key': _seed(1),
        'signing_public_key': _seed(2),
      };
      backups.backup = '{"not": "this vault"}';
      await start();
      expect(dms.state.status, CentralDmStatus.otherVault);

      // This device's vault was kept: the backup is replaced by it.
      backups.backup = null;
      await dms.retryReady();
      await _settle();

      expect(dms.state.status, CentralDmStatus.ready);
      expect(central.publishedChatKeys, [
        (await vault.getChatIdentityForHost(_host)).publicKeyBase64,
      ]);
    });

    test('its own keys already published are not written again', () async {
      await start();
      expect(dms.state.status, CentralDmStatus.ready);
      expect(central.publishedChatKeys, isEmpty);
    });
  });

  test(
    'a first page that could not be read says so and can be retried',
    () async {
      await start();
      central.latest = APIResponse.error(
        'down',
        errorCode: ErrorCode.serverUnreachable,
      );
      await open();
      expect(dms.state.chatStatus, DmChatStatus.error);
      expect(dms.state.loadFailed, isTrue);

      central.latest = APIResponse.success({
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
      await start();
      await open();
      expect(dms.state.chatStatus, DmChatStatus.ready);

      central.answerSend = (_) =>
          APIResponse.error('timed out', errorCode: ErrorCode.serverTimeout);
      await dms.sendDm('hello');
      final held = dms.state.messages.single;
      expect(held.sendFailed, isTrue);

      // Stored all the same: central has the very envelope sent.
      central.after = [
        {
          ...central.sent.single,
          'id': 1,
          'sender_id': _me,
          'recipient_id': _peer,
          'created_at': _created,
        },
      ];
      central.answerSend = null;
      await dms.retrySend(held.id);
      await _settle();

      expect(central.sent, hasLength(1), reason: 'read first, not sent again');
      expect([for (final m in dms.state.messages) m.id], ['1']);
      expect(dms.state.messages.single.text, 'hello');
    },
  );

  test('a friend with no conversation yet keeps the composer', () async {
    await start();
    await open();
    expect(dms.state.canSendToOpen, isTrue);

    // A graph change drops the friends pages; central is asked instead.
    central.standing = FriendshipState.none;
    await dms.loadFriends();
    await _settle();
    expect(dms.state.canSendToOpen, isFalse);

    central.standing = FriendshipState.friends;
    await dms.loadFriends();
    await _settle();
    expect(dms.state.canSendToOpen, isTrue);

    // A read that failed keeps the last answer.
    central.standing = null;
    await dms.loadFriends();
    await _settle();
    expect(dms.state.canSendToOpen, isTrue);
  });

  test('a rejoin reads what changed while the connection was down', () async {
    await start();
    central.joined!(RealtimeSubscribeStatus.subscribed);
    await _settle();
    await open();
    final before = central.latestReads;

    // The first join asks nothing more; one after a dropped connection reads
    // the newest page again, so edits and deletes are seen as well as what
    // was sent (review, Nov 22).
    central.joined!(RealtimeSubscribeStatus.subscribed);
    await _settle();
    expect(central.latestReads, before + 1);
  });

  test('a ring while the conversation opens is read once it has', () async {
    await start();
    final opening = dms.openConversation(
      peerId: _peer,
      peerHandle: 'peer',
      peerChatKey: _seed(5),
      peerSigningKey: _seed(6),
    );
    // Rung before the page is in: the page may have been read before the
    // message was stored.
    central.joined!(RealtimeSubscribeStatus.subscribed);
    await Future<void>.delayed(Duration.zero);
    central.joined!(RealtimeSubscribeStatus.subscribed);
    await opening;
    await _settle();
    expect(dms.state.chatStatus, DmChatStatus.ready);
    expect(central.afterReads, greaterThanOrEqualTo(1));
  });

  group('what a change costs (review, Nov 27)', () {
    test('a graph ring this device caused is not read twice', () async {
      await start();
      final before = central.countReads;

      central.graph!('this-device');
      await _settle();
      expect(central.countReads, before, reason: 'its own echo');

      central.graph!('another-device');
      await _settle();
      expect(central.countReads, before + 1);

      // No session behind it: a moderator, an account deleted.
      central.graph!(null);
      await _settle();
      expect(central.countReads, before + 2);
    });

    test('a burst of messages reads the row and the chat once more', () async {
      await start();
      await open();
      final rows = central.rowReads;
      final after = central.afterReads;

      for (var i = 0; i < 10; i++) {
        central.rang!(_peer);
      }
      await _settle();

      // One read running and one turn after it, for everyone who rang.
      expect(central.rowReads - rows, lessThanOrEqualTo(2));
      expect(central.afterReads - after, lessThanOrEqualTo(2));
      expect(central.rowReads - rows, greaterThanOrEqualTo(1));
    });

    test('a send re-reads its own row, not the whole page', () async {
      await start();
      await open();
      final pages = central.pageReads;
      final rows = central.rowReads;

      await dms.sendDm('hello');
      await _settle();

      expect(central.pageReads, pages);
      expect(central.rowReads, rows + 1);
    });

    test(
      'a listed conversation opens without asking where you stand',
      () async {
        central.rows = [
          {
            'peer_id': _peer,
            'handle': 'peer',
            'chat_public_key': _seed(5),
            'signing_public_key': _seed(6),
            'state': 'friends',
            'unread': 0,
            'latest_inbound': 0,
            'last_message': null,
          },
        ];
        await start();
        final asked = central.standingReads;

        await open();
        expect(central.standingReads, asked);
        expect(dms.state.canSendToOpen, isTrue);
      },
    );
  });
}
