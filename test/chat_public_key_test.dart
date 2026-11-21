import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/dm_conversation.dart';
import 'package:rift/logic/services/new_message_notifier.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// Found in review (Nov 21): every member writes their own chat key and
/// nothing checks it, so one that would not decode threw out of the code
/// reading a whole list — a single member emptied everyone's DM list, and
/// stopped a channel's key reaching anybody new.
///
/// And the DM notifier, which keyed on message ids seen: deleting the newest
/// message made the one before it news again.

String _key(int fill) =>
    CryptoRepository.toBase64(Uint8List.fromList(List.filled(32, fill)));

ChatMessage _message(String id, {bool mine = false}) => ChatMessage(
  id: id,
  authorId: mine ? 'me' : 'peer',
  authorName: mine ? 'Me' : 'Peer',
  text: 'hello',
  sentAt: DateTime(2026, 11, 21),
  isMine: mine,
);

DmConversation _conversation(String peerId, ChatMessage? last) =>
    DmConversation(peerId: peerId, peerName: peerId, lastMessage: last);

void main() {
  group('a published chat key', () {
    test('that is one is read', () {
      expect(CryptoRepository.chatPublicKeyOrNull(_key(3)), hasLength(32));
    });

    test('that is not one is no key', () {
      expect(CryptoRepository.chatPublicKeyOrNull(null), isNull);
      expect(CryptoRepository.chatPublicKeyOrNull('x'), isNull);
      expect(CryptoRepository.chatPublicKeyOrNull('!!not base64!!'), isNull);
      expect(
        CryptoRepository.chatPublicKeyOrNull(
          CryptoRepository.toBase64(Uint8List(31)),
        ),
        isNull,
      );
    });

    test('sealing a keyring skips the bad one and seals the rest', () async {
      final crypto = CryptoRepository();
      final entries = await crypto.sealKeyringEntries(
        key: crypto.generateChannelKey(),
        members: [
          {'user_id': 'good', 'chat_public_key': _key(9)},
          {'user_id': 'bad', 'chat_public_key': 'x'},
          {'user_id': 'none', 'chat_public_key': null},
          {'user_id': 'also-good', 'chat_public_key': _key(11)},
        ],
      );
      expect([for (final e in entries) e['user_id']], ['good', 'also-good']);
    });
  });

  group('the DM notifier', () {
    late NewMessageNotifier notifier;
    List<DmConversation> scan(
      List<DmConversation> list, {
      bool Function(DmConversation)? muted,
    }) => notifier.scan(list, titleFor: (c) => c.peerName, muted: muted);

    setUp(() => notifier = NewMessageNotifier());

    test('the first look announces nothing; a new message is news', () {
      expect(scan([_conversation('a', _message('5'))]), isEmpty);
      final fresh = scan([_conversation('a', _message('6'))]);
      expect([for (final c in fresh) c.peerId], ['a']);
    });

    test('a deleted newest message does not make the one before news', () {
      scan([_conversation('a', _message('4'))]);
      scan([_conversation('a', _message('5'))]);
      // 5 deleted: 4 is the head again.
      expect(scan([_conversation('a', _message('4'))]), isEmpty);
    });

    test('nor does one of ours being deleted', () {
      scan([_conversation('a', _message('4'))]);
      scan([_conversation('a', _message('5', mine: true))]);
      expect(scan([_conversation('a', _message('4'))]), isEmpty);
    });

    test('a muted conversation announces nothing, then or once unmuted', () {
      scan([_conversation('a', _message('1'))]);
      expect(
        scan([_conversation('a', _message('2'))], muted: (_) => true),
        isEmpty,
      );
      expect(scan([_conversation('a', _message('2'))]), isEmpty);
      expect(scan([_conversation('a', _message('3'))]), hasLength(1));
    });
  });
}
