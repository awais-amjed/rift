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
}
