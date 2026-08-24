import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/chat_notice.dart';

/// One wording for every path that raises a notification. The point of the
/// class is that the open channel, the DM scan and the push isolate cannot
/// disagree about the same message, so these tests are about the sentence.
void main() {
  group('ChatNotice.channel', () {
    test('names the room', () {
      final notice = ChatNotice.channel(
        author: 'Alice',
        channel: 'general',
        text: 'morning',
      );
      expect(notice.title, 'Alice in #general');
      expect(notice.body, 'morning');
    });

    test('being named reads differently from being in the room', () {
      final notice = ChatNotice.channel(
        author: 'Alice',
        channel: 'general',
        text: 'hey @bob look at this',
        mentionable: {'bob'},
      );
      expect(notice.title, 'Alice mentioned you in #general');
    });

    test('somebody else being named is not being named', () {
      final notice = ChatNotice.channel(
        author: 'Alice',
        channel: 'general',
        text: 'hey @carol look at this',
        mentionable: {'bob'},
      );
      expect(notice.title, 'Alice in #general');
    });

    test('the count goes in the title, so the body stays the message', () {
      final notice = ChatNotice.channel(
        author: 'Alice',
        channel: 'general',
        text: 'and another thing',
        unread: 3,
      );
      expect(notice.title, 'Alice in #general (3)');
      expect(notice.body, 'and another thing');
    });

    test('one unread is not counted', () {
      final notice = ChatNotice.channel(
        author: 'Alice',
        channel: 'general',
        text: 'hi',
        unread: 1,
      );
      expect(notice.title, isNot(contains('(')));
    });
  });

  group('ChatNotice.direct', () {
    test('the sender is the whole context', () {
      final notice = ChatNotice.direct(author: 'noor', text: 'you around?');
      expect(notice.title, 'noor');
      expect(notice.body, 'you around?');
    });

    test('counts the same way a channel does', () {
      final notice = ChatNotice.direct(author: 'noor', text: 'ok', unread: 2);
      expect(notice.title, 'noor (2)');
    });
  });

  group('preview', () {
    test('an attachment-only message is not an empty one', () {
      expect(ChatNotice.preview(''), ChatNotice.attachmentPreview);
      expect(
        ChatNotice.direct(author: 'noor', text: '').body,
        ChatNotice.attachmentPreview,
      );
      expect(
        ChatNotice.channel(author: 'Alice', channel: 'general', text: '').body,
        ChatNotice.attachmentPreview,
      );
    });

    test('text is passed through untouched', () {
      expect(ChatNotice.preview('  spaced  '), '  spaced  ');
    });
  });
}
