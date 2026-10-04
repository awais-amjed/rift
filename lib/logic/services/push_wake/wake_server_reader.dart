import 'dart:typed_data';

import 'package:rift_crypto/rift_crypto.dart';

import '../../../data/classes/api_response.dart';
import '../../../data/classes/dm_call.dart';
import '../../../data/enums/notification_level.dart';
import '../../../data/repositories/server_repository.dart';
import '../chat_notice.dart';
import '../mentions.dart';
import '../siws_sign_in.dart';
import 'wake_calls.dart';
import 'wake_dm_scan.dart';
import 'wake_envelope.dart';
import 'wake_index.dart';
import 'wake_item.dart';
import 'wake_marks.dart';

part 'wake_channel_keys.dart';
part 'wake_server_channels.dart';

/// Over the helper budget and one job: reading one server from a push-woken
/// isolate. Its channels and keys are already parts.
///
/// Reading one self-hosted server from the push background isolate.
///
/// The isolate has nothing: no cubits, no session, no keys in memory. What it
/// does have is the master seed, and everything else follows from it — the
/// Ed25519 identity that signs a fresh SIWS login, and the X25519 identity
/// that unwraps a channel key.
///
/// Signing in from scratch each time rather than reusing whatever session the
/// app last had is deliberate. SIWS is stateless: signing a message with a
/// derived key costs one round trip and leaves nothing shared behind. Reusing
/// the app's session would mean refreshing it, and a refresh token rotated by
/// an isolate is one the still-running app is about to be logged out by.
class WakeServerReader with _WakeChannelKeysMixin, _WakeChannelsMixin {
  @override
  final CryptoRepository _crypto;
  @override
  final ServerRepository _repo;
  final WakeDmScan _dms;

  WakeServerReader({
    CryptoRepository? crypto,
    ServerRepository? repo,
    WakeDmScan? dms,
  }) : _crypto = crypto ?? CryptoRepository(),
       _repo = repo ?? ServerRepository(),
       _dms = dms ?? WakeDmScan(crypto: crypto);

  /// How many conversations one wake will speak about. A phone that has been
  /// off for a day can come back to a dozen unread channels, and a dozen
  /// notifications at once is a wall, not news.
  static const maxScopes = 5;

  /// What is new on [server] that this device has not been told about.
  ///
  /// With [calls], also which DM calls started or stopped ringing here since
  /// the last wake — added to [callChanges]. A call is asked about first: it
  /// is the one thing on the server that will not wait.
  Future<WakeHarvest> read(
    WakeServer server,
    Uint8List seed,
    WakeMarks marks, {
    WakeCalls? calls,
    List<WakeCallChange>? callChanges,
  }) async {
    final token = await _signIn(server, seed);
    if (token == null) return failedHarvest;

    if (calls != null && callChanges != null) {
      final answer = await _repo.myDmCalls(
        server.supabaseUrl,
        anonKey: server.anonKey,
        bearerToken: token,
        known: calls.shownOn(server.id),
      );
      if (answer.success) {
        callChanges.addAll(
          calls.apply(
            serverId: server.id,
            myId: server.userId,
            fetched: DmCall.listFrom(answer.data),
            now: DateTime.now(),
          ),
        );
      }
    }

    final unread = await _repo.unreadCounts(
      server.supabaseUrl,
      anonKey: server.anonKey,
      bearerToken: token,
    );
    final counts = unread.data as Map<String, dynamic>?;
    if (!unread.success || counts == null) return failedHarvest;

    // `unread_counts()` answers with the levels beside the counts,
    // so the isolate learns what may interrupt in the same round trip
    // that tells it what is waiting — and cannot end up drawing on one and
    // deciding on the other.
    final prefs = counts['prefs'];
    // The server's own level, where it has one. Everything inside it falls
    // back to this before its own default — `NotificationLevel.resolve` is the
    // one copy of that order on the client, and `app.notify_level` is the one
    // copy on the server.
    final serverLevel = NotificationLevel.mapFrom(
      prefs is Map ? prefs['servers'] : null,
      fallback: null,
    )[server.id];
    return (
      items: [
        ...await _channelItems(
          server,
          seed,
          marks,
          token,
          positiveCounts(counts, 'channels'),
          // Every stored level, as the app keeps them — see
          // `ServerNotificationsCubit._seed`.
          NotificationLevel.mapFrom(
            prefs is Map ? prefs['channels'] : null,
            fallback: null,
          ),
          serverLevel,
        ),
        ...await _dmItems(
          server,
          seed,
          marks,
          token,
          positiveCounts(counts, 'dms'),
          NotificationLevel.mapFrom(
            prefs is Map ? prefs['dms'] : null,
            fallback: null,
          ),
          serverLevel,
        ),
      ],
      failed: false,
    );
  }

  /// The scopes with something waiting. Zeroes are dropped here rather than
  /// checked at each use — an `unread_counts` answer is a map of everything,
  /// and only the non-empty half is a reason to wake anyone.
  static Map<String, int> positiveCounts(
    Map<String, dynamic> data,
    String key,
  ) {
    final raw = data[key];
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is int && (entry.value as int) > 0)
          '${entry.key}': entry.value as int,
    };
  }

  /// A fresh SIWS session, signed with the key the seed derives for this
  /// (host, server) pair. Public for the one other thing a woken isolate does
  /// on a server: declining a call from its notification.
  Future<String?> signIn(WakeServer server, Uint8List seed) =>
      _signIn(server, seed);

  Future<String?> _signIn(WakeServer server, Uint8List seed) async {
    try {
      final host = Uri.parse(server.supabaseUrl).host;
      final identity = await _crypto.deriveServerIdentity(
        masterSeed: seed,
        host: host,
        serverId: server.id,
        version: server.keyVersion,
      );
      final response = await siwsSignIn(
        repository: _repo,
        crypto: _crypto,
        supabaseUrl: server.supabaseUrl,
        identity: identity,
      );
      if (!response.success) return null;
      return (response.data as Map<String, dynamic>?)?['access_token']
          as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ChatIdentity?> _chatIdentity(WakeServer server, Uint8List seed) async {
    try {
      return await _crypto.deriveChatIdentity(
        masterSeed: seed,
        host: Uri.parse(server.supabaseUrl).host,
        version: CryptoRepository.chatIdentityVersion,
      );
    } catch (_) {
      return null;
    }
  }

  /// The DM half is [WakeDmScan]'s: a self-hosted server and central answer
  /// `dm_conversations()` in the same shape, so the reading of it is one piece
  /// of code and only the transport differs.
  Future<List<WakeItem>> _dmItems(
    WakeServer server,
    Uint8List seed,
    WakeMarks marks,
    String token,
    Map<String, int> unread,
    Map<String, NotificationLevel> levels,
    NotificationLevel? serverLevel,
  ) async {
    if (unread.isEmpty) return const [];
    final identity = await _chatIdentity(server, seed);
    if (identity == null) return const [];

    final response = await _repo.listDmConversations(
      server.supabaseUrl,
      anonKey: server.anonKey,
      bearerToken: token,
    );
    if (!response.success) return const [];
    final conversations =
        (response.data as Map<String, dynamic>?)?['conversations'] as List?;
    if (conversations == null) return const [];

    return _dms.scan(
      conversations: conversations.cast<Map<String, dynamic>>(),
      unread: unread,
      myUserId: server.userId,
      myChatKeyPair: identity.keyPair,
      scopePrefix: 'dm:${server.id}',
      marks: marks,
      levels: levels,
      serverLevel: serverLevel,
      limit: maxScopes,
    );
  }

  /// A `list_messages` page, newest first, or empty when the read failed.
  static List<Map<String, dynamic>> messagesOf(APIResponse response) {
    if (!response.success) return const [];
    final rows = (response.data as Map<String, dynamic>?)?['messages'] as List?;
    if (rows == null) return const [];
    return rows.cast<Map<String, dynamic>>();
  }
}
