import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/dm_unread_scan.dart';

const me = 'me';
const alice = 'alice';
const bob = 'bob';

Map<String, dynamic> row(int id, String from, String to) => {
  'id': id,
  'sender_id': from,
  'recipient_id': to,
};

void main() {
  group('DmUnreadScan', () {
    test('counts inbound messages above the cursor, per peer', () {
      final scan = DmUnreadScan.of(
        rows: [
          row(5, alice, me),
          row(4, alice, me),
          row(3, bob, me),
          row(2, alice, me),
        ],
        myUserId: me,
        cursors: {alice: 2},
      );
      expect(scan.counts[alice], 2); // 4 and 5, not 2
      expect(scan.counts[bob], 1); // no cursor → everything counts
    });

    test('a fully-read conversation is absent, not zero', () {
      // The UI asks "is there a count", so an empty map has to mean nothing
      // unread rather than a map full of zeros.
      final scan = DmUnreadScan.of(
        rows: [row(2, alice, me), row(1, alice, me)],
        myUserId: me,
        cursors: {alice: 2},
      );
      expect(scan.counts.containsKey(alice), isFalse);
    });

    test('own messages never count as unread', () {
      final scan = DmUnreadScan.of(
        rows: [row(9, me, alice), row(8, me, alice)],
        myUserId: me,
        cursors: const {},
      );
      expect(scan.counts, isEmpty);
      // ...and they don't move the cursor either: replying is not reading.
      expect(scan.latestInbound, isEmpty);
    });

    test('latestInbound is the newest inbound id, whatever the row order', () {
      final scan = DmUnreadScan.of(
        rows: [
          row(3, alice, me),
          row(7, alice, me),
          row(5, alice, me),
          row(99, me, alice), // outbound, and higher than any inbound
        ],
        myUserId: me,
        cursors: const {},
      );
      expect(scan.latestInbound[alice], 7);
    });

    test('latestInbound is reported even when nothing is unread', () {
      // Marking an already-read conversation read must not rewind the cursor.
      final scan = DmUnreadScan.of(
        rows: [row(4, alice, me)],
        myUserId: me,
        cursors: {alice: 4},
      );
      expect(scan.counts, isEmpty);
      expect(scan.latestInbound[alice], 4);
    });

    test('empty input yields empty maps', () {
      final scan = DmUnreadScan.of(
        rows: const [],
        myUserId: me,
        cursors: const {},
      );
      expect(scan.counts, isEmpty);
      expect(scan.latestInbound, isEmpty);
    });

    test('malformed rows are skipped rather than thrown on', () {
      // Rows come off the wire as untyped maps; one bad row must not take the
      // whole conversation list down with it.
      final scan = DmUnreadScan.of(
        rows: [
          {'id': null, 'sender_id': alice, 'recipient_id': me},
          {'id': 3, 'sender_id': null, 'recipient_id': me},
          row(4, alice, me),
        ],
        myUserId: me,
        cursors: const {},
      );
      expect(scan.counts[alice], 1);
      expect(scan.latestInbound[alice], 4);
    });
  });
}
