import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/presence_ration.dart';

void main() {
  group('the presence ration', () {
    final now = DateTime(2026, 8, 9, 12, 0, 0);

    List<DateTime> secondsAgo(List<int> seconds) => [
      for (final s in seconds) now.subtract(Duration(seconds: s)),
    ];

    test('spends freely while there is room in the window', () {
      expect(
        PresenceRation.publishWait(recent: const [], now: now),
        Duration.zero,
      );
      expect(
        PresenceRation.publishWait(recent: secondsAgo([1, 2, 3]), now: now),
        Duration.zero,
      );
    });

    test('holds back once the window is full', () {
      // Realtime allows five presence events per 30s and *terminates the
      // channel* on the sixth, so this is what keeps us alive, not a nicety.
      final wait = PresenceRation.publishWait(
        recent: secondsAgo([25, 20, 15, 10]),
        now: now,
      );
      // Room again once the oldest (25s ago) leaves the window.
      expect(wait, greaterThan(const Duration(seconds: 4)));
      expect(wait, lessThan(const Duration(seconds: 8)));
    });

    test('forgets what has fallen out of the window', () {
      expect(
        PresenceRation.publishWait(
          recent: secondsAgo([120, 90, 60, 31]),
          now: now,
        ),
        Duration.zero,
      );
    });

    test('never asks for more than one window of patience', () {
      final wait = PresenceRation.publishWait(
        recent: secondsAgo([0, 0, 0, 0]),
        now: now,
      );
      expect(wait, lessThanOrEqualTo(const Duration(seconds: 31)));
    });
  });

  group('spending', () {
    final now = DateTime(2026, 8, 9, 12, 0, 0);

    test('records the new update and forgets the expired ones', () {
      final recent = [
        now.subtract(const Duration(seconds: 45)),
        now.subtract(const Duration(seconds: 31)),
        now.subtract(const Duration(seconds: 10)),
      ];

      final spent = PresenceRation.spend(recent, now);

      expect(spent, hasLength(2));
      expect(spent.last, now);
      expect(spent.first, now.subtract(const Duration(seconds: 10)));
    });
  });

  group('rebuild backoff', () {
    test('starts short and grows', () {
      expect(
        PresenceRation.rebuildDelay(1),
        greaterThan(PresenceRation.rebuildDelay(0)),
      );
    });

    test('is capped, so a broken server is not a reconnect storm', () {
      for (final attempt in [8, 20, 1000]) {
        expect(
          PresenceRation.rebuildDelay(attempt),
          const Duration(seconds: 30),
        );
      }
    });
  });

  group('presence healing', () {
    test('re-tracks when our own entry is missing from the sync', () {
      // What the bug looked like from the inside: we believe we published an
      // entry, and the state the server is broadcasting doesn't have one.
      expect(
        PresenceRation.shouldRetrack(
          tracked: true,
          localUserId: 'u1',
          onlineUserIds: {'u2', 'u3'},
        ),
        isTrue,
      );
    });

    test('leaves a healthy entry alone', () {
      expect(
        PresenceRation.shouldRetrack(
          tracked: true,
          localUserId: 'u1',
          onlineUserIds: {'u1', 'u2'},
        ),
        isFalse,
      );
    });

    test('does not fight a track that was never made', () {
      // Nothing to heal before we've claimed to be tracked — otherwise every
      // sync between subscribing and tracking would queue another attempt.
      expect(
        PresenceRation.shouldRetrack(
          tracked: false,
          localUserId: 'u1',
          onlineUserIds: <String>{},
        ),
        isFalse,
      );
    });

    test('does nothing while we have no identity on this server', () {
      expect(
        PresenceRation.shouldRetrack(
          tracked: true,
          localUserId: null,
          onlineUserIds: <String>{},
        ),
        isFalse,
      );
    });
  });
}
