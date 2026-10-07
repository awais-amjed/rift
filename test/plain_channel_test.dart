import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/message_body.dart';
import 'package:rift/data/enums/message_origin.dart';
import 'package:rift/presentation/common/chat/message_row/message_origin_badge.dart';

/// Channels whose encryption was turned off (ARCHITECTURE.md §4). Encrypted is
/// the default a missing field must fall back to, and the badge may only go
/// quiet where the channel itself says it is not encrypted.
void main() {
  group('Channel.isEncrypted', () {
    Map<String, dynamic> row([Map<String, dynamic> extra = const {}]) => {
      'id': 'c1',
      'name': 'general',
      'channel_type': 'text',
      ...extra,
    };

    test('is encrypted unless the server says otherwise', () {
      expect(Channel.fromJson(row()).isEncrypted, isTrue);
      expect(Channel.fromJson(row({'is_encrypted': null})).isEncrypted, isTrue);
      expect(
        Channel.fromJson(row({'is_encrypted': false})).isEncrypted,
        isFalse,
      );
    });

    test('a private or voice channel stays encrypted whatever it says', () {
      expect(
        Channel.fromJson(
          row({'is_encrypted': false, 'is_private': true}),
        ).isEncrypted,
        isTrue,
      );
      expect(
        Channel.fromJson(
          row({'is_encrypted': false, 'channel_type': 'voice'}),
        ).isEncrypted,
        isTrue,
      );
    });

    test('survives a round trip', () {
      final plain = Channel.fromJson(row({'is_encrypted': false}));
      expect(Channel.fromJson(plain.toJson()).isEncrypted, isFalse);
    });
  });

  group('MessageOriginBadge.isNeededFor', () {
    ChatMessage message({
      bool isEncrypted = true,
      bool inPlainChannel = false,
      MessageOrigin origin = MessageOrigin.member,
    }) => ChatMessage(
      id: '1',
      authorId: 'a',
      authorName: 'A',
      text: 'hi',
      sentAt: DateTime(2026),
      isMine: false,
      isEncrypted: isEncrypted,
      inPlainChannel: inPlainChannel,
      origin: origin,
    );

    test('a member in the clear is badged in an encrypted channel', () {
      expect(
        MessageOriginBadge.isNeededFor(message(isEncrypted: false)),
        isTrue,
      );
    });

    test('but not where the channel itself is not encrypted', () {
      expect(
        MessageOriginBadge.isNeededFor(
          message(isEncrypted: false, inPlainChannel: true),
        ),
        isFalse,
      );
    });

    test('a webhook is badged everywhere', () {
      expect(
        MessageOriginBadge.isNeededFor(
          message(
            isEncrypted: false,
            inPlainChannel: true,
            origin: MessageOrigin.webhook,
          ),
        ),
        isTrue,
      );
    });
  });

  group('MessageBody.encodeInClear', () {
    test('is the bare text when that is all there is', () {
      expect(const MessageBody(text: 'hello').encodeInClear(), 'hello');
      expect(MessageBody.decode('hello').text, 'hello');
    });

    test('keeps the structure when there is more than text', () {
      const body = MessageBody(text: 'answer', replyToId: '42');
      final decoded = MessageBody.decode(body.encodeInClear());
      expect(decoded.text, 'answer');
      expect(decoded.replyToId, '42');
    });
  });
}
