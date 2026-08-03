import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/notifications/server_notifications_cubit.dart';

void main() {
  group('NotificationsState unread math', () {
    const state = NotificationsState(
      unreadByServer: {
        'srvA': {'c1': 2, 'c2': 3},
        'srvB': {'c9': 1},
      },
    );

    test('unreadForChannel returns the channel count, 0 when absent', () {
      expect(state.unreadForChannel('srvA', 'c1'), 2);
      expect(state.unreadForChannel('srvA', 'nope'), 0);
      expect(state.unreadForChannel('nope', 'c1'), 0);
    });

    test('unreadForServer sums a server\'s channels', () {
      expect(state.unreadForServer('srvA'), 5);
      expect(state.unreadForServer('srvB'), 1);
      expect(state.unreadForServer('nope'), 0);
    });

    test('totalUnreadExcept excludes the given server', () {
      expect(state.totalUnreadExcept('srvA'), 1); // only srvB
      expect(state.totalUnreadExcept('srvB'), 5); // only srvA
      expect(state.totalUnreadExcept(null), 6); // everything
      expect(state.totalUnreadExcept('nope'), 6);
    });

    test('empty state is all zeros', () {
      const empty = NotificationsState();
      expect(empty.unreadForServer('srvA'), 0);
      expect(empty.totalUnreadExcept(null), 0);
    });

    test('copyWith replaces the map', () {
      final next = state.copyWith(
        unreadByServer: {
          'x': {'y': 9},
        },
      );
      expect(next.unreadForServer('x'), 9);
      expect(next.unreadForServer('srvA'), 0);
    });
  });

  group('NotificationsState transforms', () {
    test('incrementing starts from zero and accumulates', () {
      final state = const NotificationsState()
          .incremented('s1', 'c1')
          .incremented('s1', 'c1')
          .incremented('s1', 'c2');
      expect(state.unreadForChannel('s1', 'c1'), 2);
      expect(state.unreadForServer('s1'), 3);
    });

    test('clearing the last channel drops the server key entirely', () {
      final state = const NotificationsState()
          .incremented('s1', 'c1')
          .clearedChannel('s1', 'c1');
      expect(state.unreadByServer.containsKey('s1'), isFalse);
    });

    test('clearing a channel leaves its siblings alone', () {
      final state = const NotificationsState()
          .incremented('s1', 'c1')
          .incremented('s1', 'c2')
          .clearedChannel('s1', 'c1');
      expect(state.unreadForChannel('s1', 'c1'), 0);
      expect(state.unreadForChannel('s1', 'c2'), 1);
    });

    test('clearing something already clear returns the same instance', () {
      // The cubit clears on every focus change and every message in the open
      // channel; returning `this` is what stops those from emitting.
      final state = const NotificationsState().incremented('s1', 'c1');
      expect(state.clearedChannel('s1', 'other'), same(state));
      expect(state.clearedChannel('other', 'c1'), same(state));
      expect(state.clearedServer('other'), same(state));
    });

    test('a re-seed replaces a server wholesale', () {
      final state = const NotificationsState()
          .incremented('s1', 'stale')
          .withServerCounts('s1', {'c1': 7});
      expect(state.unreadForChannel('s1', 'stale'), 0);
      expect(state.unreadForChannel('s1', 'c1'), 7);
    });

    test('re-seeding with nothing unread removes the server', () {
      final state = const NotificationsState()
          .incremented('s1', 'c1')
          .incremented('s2', 'c2')
          .withServerCounts('s1', const {});
      expect(state.unreadByServer.containsKey('s1'), isFalse);
      expect(state.unreadForServer('s2'), 1);
    });

    test('leaving a server drops only its counts', () {
      final state = const NotificationsState()
          .incremented('s1', 'c1')
          .incremented('s2', 'c2')
          .clearedServer('s1');
      expect(state.unreadByServer.keys, ['s2']);
    });

    test('transforms never mutate the state they came from', () {
      final original = const NotificationsState().incremented('s1', 'c1');
      original.incremented('s1', 'c1');
      original.clearedChannel('s1', 'c1');
      original.withServerCounts('s1', {'c9': 9});
      expect(original.unreadForChannel('s1', 'c1'), 1);
      expect(original.unreadForServer('s1'), 1);
    });
  });
}
