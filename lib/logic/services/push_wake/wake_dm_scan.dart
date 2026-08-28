import 'package:cryptography/cryptography.dart' show SimpleKeyPair;

import '../../../data/enums/notification_level.dart';
import 'package:rift_crypto/rift_crypto.dart';
import '../chat_notice.dart';
import 'wake_envelope.dart';
import 'wake_item.dart';
import 'wake_marks.dart';

/// Turning a `dm_conversations()` answer into things worth saying.
///
/// Shared by both tiers on purpose. A self-hosted server and central return
/// the same shape from the same-named function — each peer's identity material
/// beside their latest envelope — because both were built to let one client
/// path read them. The isolate is that client path, asleep.
class WakeDmScan {
  final CryptoRepository _crypto;

  WakeDmScan({CryptoRepository? crypto})
    : _crypto = crypto ?? CryptoRepository();

  /// One item per unread conversation, newest message quoted.
  ///
  /// [scopePrefix] separates the two tiers and the several servers within one:
  /// a peer id is only unique next to the place it came from, and the scope is
  /// what decides which notification this replaces.
  ///
  /// [levels] mutes conversations, and [serverLevel] is what one falls back to
  /// when it has no level of its own — muting a server quiets its DMs too. A
  /// DM has nobody in it to be named among, so only [NotificationLevel.none]
  /// means anything here: a level of `mentions` on one reads as `all`, the same
  /// way the ring trigger reads it, because the alternative is silently losing
  /// somebody every message they send. Central passes no [serverLevel] — it
  /// has no servers.
  Future<List<WakeItem>> scan({
    required List<Map<String, dynamic>> conversations,
    required Map<String, int> unread,
    required String myUserId,
    required SimpleKeyPair myChatKeyPair,
    required String scopePrefix,
    required WakeMarks marks,
    required int limit,
    Map<String, NotificationLevel> levels = const {},
    NotificationLevel? serverLevel,
  }) async {
    final items = <WakeItem>[];
    for (final convo in conversations) {
      if (items.length >= limit) break;

      final peerId = convo['peer_id'] as String?;
      final count = peerId == null ? null : unread[peerId];
      final row = (convo['last_message'] as Map?)?.cast<String, dynamic>();
      final peerChatKey = convo['peer_chat_public_key'] as String?;
      final peerSigningKey = convo['peer_public_key'] as String?;
      if (peerId == null ||
          count == null ||
          row == null ||
          peerChatKey == null ||
          peerSigningKey == null) {
        continue;
      }

      final level = NotificationLevel.resolve(
        scope: levels[peerId],
        server: serverLevel,
        fallback: NotificationLevel.dmDefault,
      );
      if (level.isMuted) continue;

      final scope = '$scopePrefix:$peerId';
      final id = row['id'] as int?;
      if (id == null || !marks.isFresh(scope, id)) continue;
      // Our own message can be the newest in a conversation that still has
      // something unread further back. Announcing it would tell the user what
      // they themselves said.
      if (row['sender_id'] != peerId) continue;

      final text = await _openFrom(
        row,
        peerId: peerId,
        myUserId: myUserId,
        myChatKeyPair: myChatKeyPair,
        peerChatKey: peerChatKey,
        peerSigningKey: peerSigningKey,
      );
      if (text == null) continue;

      items.add(
        WakeItem(
          scope: scope,
          messageId: id,
          notice: ChatNotice.direct(
            author: convo['peer_name'] as String? ?? 'Someone',
            text: text,
            unread: count,
          ),
        ),
      );
    }
    return items;
  }

  Future<String?> _openFrom(
    Map<String, dynamic> row, {
    required String peerId,
    required String myUserId,
    required SimpleKeyPair myChatKeyPair,
    required String peerChatKey,
    required String peerSigningKey,
  }) async {
    try {
      final key = await _crypto.deriveDmKey(
        myKeyPair: myChatKeyPair,
        theirPublicKey: CryptoRepository.fromBase64(peerChatKey),
      );
      return openWakeEnvelope(
        _crypto,
        row,
        key: key,
        contextId: MessageEnvelope.conversationContext(myUserId, peerId),
        senderKeyB64: peerSigningKey,
      );
    } catch (_) {
      return null;
    }
  }
}
