import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/enums/error_code.dart';
import 'package:rift/data/repositories/server_db.dart';
import 'package:rift/logic/services/chat_message_ops.dart';
import 'package:rift/logic/services/outbox.dart';
import 'package:supabase/supabase.dart' show PostgrestException;

/// A send that fails used to take the typed text with it: the optimistic row
/// was removed, a toast said "Failed to send message", and the sentence was
/// gone. The outbox is what keeps it — but only when keeping it is honest,
/// which is the distinction most of these tests are about.
void main() {
  ChatMessage row(String id, {String text = 'hello', DateTime? at}) =>
      ChatMessage(
        id: id,
        authorId: 'me',
        authorName: 'Me',
        text: text,
        sentAt: at ?? DateTime(2026, 9, 4, 12),
        isMine: true,
        isPending: true,
        sendFailed: true,
      );

  OutboxEntry entry(String id, {String to = 'chan', DateTime? at}) =>
      OutboxEntry(
        destination: to,
        row: row(id, at: at),
      );

  group('what is worth keeping', () {
    test('a connection that dropped is', () {
      expect(Outbox.canRetry(ErrorCode.serverUnreachable), isTrue);
      expect(Outbox.canRetry(ErrorCode.serverTimeout), isTrue);
    });

    test('a server that answered is not', () {
      // Each of these is the server having considered the message and said no.
      // Offering "try again" on one is a button that cannot work — and worse,
      // it tells the reader the message might still go.
      for (final code in [
        ErrorCode.quotaExceeded,
        ErrorCode.permissionDenied,
        'not_friends',
        '42501',
      ]) {
        expect(Outbox.canRetry(code), isFalse, reason: code);
      }
    });

    test('and neither is a failure that named no reason', () {
      // An exception that escaped the send path is a bug, and bugs are the
      // same next time. Guessing "retryable" here would put a permanent
      // retry button under a message that can never leave.
      expect(Outbox.canRetry(null), isFalse);
    });
  });

  group('the code a real drop arrives as', () {
    // Everything above hangs off this. If a lost connection stopped mapping to
    // one of the two retryable codes, every failed send would go back to being
    // deleted with a toast — and nothing else in these tests would notice.
    test('a socket that never opened is retryable', () async {
      final response = await ServerDb.run(
        () async => throw const SocketException('Connection refused'),
      );
      expect(response.success, isFalse);
      expect(response.errorCode, ErrorCode.serverUnreachable);
      expect(Outbox.canRetry(response.errorCode), isTrue);
    });

    test('a host that did not resolve is too', () async {
      final response = await ServerDb.run(
        () async => throw const SocketException('Failed host lookup: rift'),
      );
      expect(Outbox.canRetry(response.errorCode), isTrue);
    });

    test('but a refusal that came back over a working socket is not', () async {
      // A quota trigger raising in Postgres reaches the client with its own
      // code. The connection was fine; the answer was no.
      final response = await ServerDb.run(
        () async =>
            throw PostgrestException(message: 'quota_exceeded', code: 'P0001'),
      );
      expect(response.errorCode, 'quota_exceeded');
      expect(Outbox.canRetry(response.errorCode), isFalse);
    });
  });

  group('holding and taking', () {
    test('take hands the entry back exactly once', () {
      final outbox = Outbox()..hold(entry('pending-0'));
      expect(outbox.take('pending-0')?.pendingId, 'pending-0');
      // The second tap of a double-tap finds nothing, which is what stops one
      // message being sent twice.
      expect(outbox.take('pending-0'), isNull);
      expect(outbox.length, 0);
    });

    test('a conversation keeps only its own', () {
      final outbox = Outbox()
        ..hold(entry('a', to: 'chan-1'))
        ..hold(entry('b', to: 'chan-2'))
        ..hold(entry('c', to: 'chan-1'));

      expect(outbox.rowsFor('chan-1').map((r) => r.id), ['a', 'c']);
      expect(outbox.rowsFor('chan-2').map((r) => r.id), ['b']);

      outbox.dropDestination('chan-1');
      expect(outbox.rowsFor('chan-1'), isEmpty);
      expect(outbox.rowsFor('chan-2'), hasLength(1));
    });

    test('rows come back oldest first, whatever order they failed in', () {
      final outbox = Outbox()
        ..hold(entry('late', at: DateTime(2026, 9, 4, 15)))
        ..hold(entry('early', at: DateTime(2026, 9, 4, 9)));
      expect(outbox.rowsFor('chan').map((r) => r.id), ['early', 'late']);
    });
  });

  group('restoreInto', () {
    test('puts failed rows back under a freshly fetched page', () {
      // The point of the whole thing: click away from a conversation with an
      // unsent message in it, come back, and it is still there.
      final outbox = Outbox()..hold(entry('pending-0'));
      final restored = outbox.restoreInto([
        ChatMessage(
          id: '1',
          authorId: 'them',
          authorName: 'Them',
          text: 'hi',
          sentAt: DateTime(2026, 9, 4, 11),
          isMine: false,
        ),
      ], 'chan');

      expect(restored, hasLength(2));
      expect(restored.last.id, 'pending-0');
      expect(restored.last.sendFailed, isTrue);
    });

    test('another conversation gets nothing back', () {
      final outbox = Outbox()..hold(entry('pending-0', to: 'chan-1'));
      expect(outbox.restoreInto(const [], 'chan-2'), isEmpty);
    });

    test('a row already on screen is not added twice', () {
      final outbox = Outbox()..hold(entry('pending-0'));
      final once = outbox.restoreInto(const [], 'chan');
      expect(outbox.restoreInto(once, 'chan'), hasLength(1));
    });
  });

  group('markFailed', () {
    test('leaves the row where it is and flips the flag', () {
      final messages = [
        ChatMessage(
          id: '1',
          authorId: 'me',
          authorName: 'Me',
          text: 'sent',
          sentAt: DateTime(2026, 9, 4, 11),
          isMine: true,
        ),
        ChatMessage(
          id: 'pending-0',
          authorId: 'me',
          authorName: 'Me',
          text: 'stuck',
          sentAt: DateTime(2026, 9, 4, 12),
          isMine: true,
          isPending: true,
        ),
      ];

      final marked = ChatMessageOps.markFailed(messages, 'pending-0');
      expect(marked, hasLength(2), reason: 'the row must not be removed');
      expect(marked.last.text, 'stuck', reason: 'the typed text survives');
      expect(marked.last.sendFailed, isTrue);
      // Still unsent — failing is not an acknowledgement.
      expect(marked.last.isPending, isTrue);
      expect(marked.first.sendFailed, isFalse);
    });
  });

  group('grouping', () {
    test('a failed message does not tuck under the one before it', () {
      // "Not sent" is drawn in the header, and only the first row of a group
      // has one — so a failed row sharing a group key with the message above
      // would be silent about the one thing it has to say.
      final sent = ChatMessage(
        id: '1',
        authorId: 'me',
        authorName: 'Me',
        text: 'a',
        sentAt: DateTime(2026, 9, 4, 12),
        isMine: true,
      );
      expect(sent.groupKey, isNot(row('pending-0').groupKey));
    });
  });

  group('mergeIncoming reports what it retired', () {
    test('so a send that timed out after landing stops being held', () {
      // The server stored it, the acknowledgement never arrived, the row was
      // marked failed. Then the message itself comes back over realtime: the
      // merge retires the row, and the entry behind it has to go too — or
      // reopening the conversation would offer to send it again.
      final pending = ChatMessage(
        id: 'pending-0',
        authorId: 'me',
        authorName: 'Me',
        text: 'landed after all',
        sentAt: DateTime(2026, 9, 4, 12),
        isMine: true,
        isPending: true,
        sendFailed: true,
      );
      final acked = ChatMessage(
        id: '77',
        authorId: 'me',
        authorName: 'Me',
        text: 'landed after all',
        sentAt: DateTime(2026, 9, 4, 12),
        isMine: true,
      );

      final result = ChatMessageOps.mergeIncoming(
        current: [pending],
        incoming: [acked],
      );

      expect(result.retired, ['pending-0']);
      expect(result.merged.map((m) => m.id), ['77']);

      final outbox = Outbox()
        ..hold(OutboxEntry(destination: 'chan', row: pending));
      for (final id in result.retired) {
        outbox.drop(id);
      }
      expect(outbox.length, 0);
    });

    test('and reports nothing when nothing was pending', () {
      final result = ChatMessageOps.mergeIncoming(
        current: const [],
        incoming: [
          ChatMessage(
            id: '1',
            authorId: 'them',
            authorName: 'Them',
            text: 'hi',
            sentAt: DateTime(2026, 9, 4, 12),
            isMine: false,
          ),
        ],
      );
      expect(result.retired, isEmpty);
    });
  });
}
