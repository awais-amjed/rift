import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/message_body.dart';
import 'package:rift/data/repositories/crypto_repository.dart';
import 'package:rift/logic/services/push_wake/wake_dm_scan.dart';
import 'package:rift/logic/services/push_wake/wake_marks.dart';

/// The push isolate opening what the app sealed.
///
/// This is the join between the two halves of the feature: the app seals a
/// message into an envelope, and a process with none of the app's state has to
/// open it from the seed alone. Everything else in the wake path is plumbing;
/// if this works, the notification can say something true.
void main() {
  const myId = '11111111-1111-1111-1111-111111111111';
  const peerId = '22222222-2222-2222-2222-222222222222';
  const host = 'example.supabase.co';

  final crypto = CryptoRepository();
  late ChatIdentity myChat;
  late ChatIdentity peerChat;
  late ServerIdentity peerSigning;

  setUpAll(() async {
    final mySeed = Uint8List.fromList(List.filled(32, 1));
    final peerSeed = Uint8List.fromList(List.filled(32, 2));
    myChat = await crypto.deriveChatIdentity(masterSeed: mySeed, host: host);
    peerChat = await crypto.deriveChatIdentity(
      masterSeed: peerSeed,
      host: host,
    );
    peerSigning = await crypto.deriveServerIdentity(
      masterSeed: peerSeed,
      host: host,
    );
  });

  /// One row as `dm_conversations()` returns it, sealed by the peer to us.
  Future<Map<String, dynamic>> conversation({
    required String text,
    int id = 10,
    String senderId = peerId,
    bool corruptSignature = false,
  }) async {
    final key = await crypto.deriveDmKey(
      myKeyPair: peerChat.keyPair,
      theirPublicKey: myChat.publicKeyBytes,
    );
    final envelope = await crypto.sealMessage(
      plaintext: MessageBody(text: text).encode(),
      messageKey: key,
      signingKeyPair: peerSigning.keyPair,
      contextId: MessageEnvelope.conversationContext(myId, peerId),
      keyVersion: 1,
    );
    final row = {
      ...envelope.toJson(),
      'id': id,
      'sender_id': senderId,
      'recipient_id': myId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      if (corruptSignature)
        'signature': CryptoRepository.toBase64(
          Uint8List.fromList(List.filled(64, 9)),
        ),
    };
    return {
      'peer_id': peerId,
      'peer_name': 'noor',
      'peer_chat_public_key': CryptoRepository.toBase64(
        peerChat.publicKeyBytes,
      ),
      'peer_public_key': CryptoRepository.toBase64(peerSigning.publicKeyBytes),
      'last_message': row,
    };
  }

  Future<List<dynamic>> scan(
    List<Map<String, dynamic>> conversations, {
    Map<String, int> unread = const {peerId: 2},
    WakeMarks? marks,
  }) => WakeDmScan(crypto: crypto).scan(
    conversations: conversations,
    unread: unread,
    myUserId: myId,
    myChatKeyPair: myChat.keyPair,
    scopePrefix: 'central',
    marks: marks ?? WakeMarks({}),
    limit: 5,
  );

  test('opens a peer envelope and quotes it', () async {
    final items = await scan([await conversation(text: 'you around?')]);
    expect(items, hasLength(1));
    expect(items.single.scope, 'central:$peerId');
    expect(items.single.messageId, 10);
    expect(items.single.notice.title, 'noor (2)');
    expect(items.single.notice.body, 'you around?');
  });

  test('a conversation with nothing unread is not spoken about', () async {
    final items = await scan(
      [await conversation(text: 'hi')],
      unread: const {},
    );
    expect(items, isEmpty);
  });

  test('a message already announced is not announced again', () async {
    final marks = WakeMarks({})..mark('central:$peerId', 10);
    final items = await scan([await conversation(text: 'hi')], marks: marks);
    expect(items, isEmpty);
  });

  test('our own newest message is never read back to us', () async {
    final items = await scan([
      await conversation(text: 'mine', senderId: myId),
    ]);
    expect(items, isEmpty);
  });

  test('a forged signature is dropped rather than shown', () async {
    final items = await scan([
      await conversation(text: 'trust me', corruptSignature: true),
    ]);
    expect(items, isEmpty);
  });

  test('a conversation missing identity material is skipped', () async {
    final convo = await conversation(text: 'hi');
    convo.remove('peer_chat_public_key');
    expect(await scan([convo]), isEmpty);
  });

  test('the limit caps how much one wake says', () async {
    final many = [
      for (var i = 0; i < 3; i++) await conversation(text: 'm$i', id: 10 + i),
    ];
    final items = await WakeDmScan(crypto: crypto).scan(
      conversations: many,
      unread: const {peerId: 1},
      myUserId: myId,
      myChatKeyPair: myChat.keyPair,
      scopePrefix: 'central',
      marks: WakeMarks({}),
      limit: 2,
    );
    expect(items, hasLength(2));
  });
}
