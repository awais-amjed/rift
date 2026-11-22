import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/enums/notification_level.dart';
import 'package:rift/logic/cubits/notifications/server_notifications_cubit.dart';

void main() {
  group('NotificationsState unread math', () {
    const state = NotificationsState(
      unreadByServer: {
        'srvA': {'c1': 2, 'c2': 3},
        'srvB': {'c9': 1},
      },
      dmUnreadByServer: {
        'srvA': {'peer1': 4},
      },
    );

    test('unreadForChannel returns the channel count, 0 when absent', () {
      expect(state.unreadForChannel('srvA', 'c1'), 2);
      expect(state.unreadForChannel('srvA', 'nope'), 0);
      expect(state.unreadForChannel('nope', 'c1'), 0);
    });

    test('unreadForDm returns the peer count, 0 when absent', () {
      expect(state.unreadForDm('srvA', 'peer1'), 4);
      expect(state.unreadForDm('srvA', 'nope'), 0);
      expect(state.unreadForDm('srvB', 'peer1'), 0);
    });

    test('a channel and a peer with the same id never collide', () {
      // Ids come from different tables; the two maps are what keeps a channel
      // named like a user id from lighting up a conversation badge.
      const clash = NotificationsState(
        unreadByServer: {
          's': {'same': 1},
        },
      );
      expect(clash.unreadForChannel('s', 'same'), 1);
      expect(clash.unreadForDm('s', 'same'), 0);
    });

    test('dmUnreadForServer sums only the DM side', () {
      expect(state.dmUnreadForServer('srvA'), 4);
      expect(state.dmUnreadForServer('srvB'), 0);
    });

    test('unreadForServer sums channels and DMs together', () {
      expect(state.unreadForServer('srvA'), 9);
      expect(state.unreadForServer('srvB'), 1);
      expect(state.unreadForServer('nope'), 0);
    });

    test('totalBadgeExcept excludes the given server, DMs included', () {
      // Every channel here is at "Only @mentions" and nothing names anybody,
      // so only srvA's DMs ask for anyone.
      expect(state.totalBadgeExcept('srvA'), 0);
      expect(state.totalBadgeExcept('srvB'), 4);
      expect(state.totalBadgeExcept(null), 4);
      expect(state.totalBadgeExcept('nope'), 4);
    });

    test('empty state is all zeros', () {
      const empty = NotificationsState();
      expect(empty.unreadForServer('srvA'), 0);
      expect(empty.dmUnreadForServer('srvA'), 0);
      expect(empty.totalBadgeExcept(null), 0);
    });

    test('copyWith replaces one map and leaves the other', () {
      final next = state.copyWith(
        unreadByServer: {
          'x': {'y': 9},
        },
      );
      expect(next.unreadForServer('x'), 9);
      expect(next.unreadForChannel('srvA', 'c1'), 0);
      expect(next.unreadForDm('srvA', 'peer1'), 4);
    });
  });

  group('NotificationsState transforms', () {
    test('incrementing starts from zero and accumulates', () {
      final state = const NotificationsState()
          .incremented('s1', 'c1', mentioned: false)
          .incremented('s1', 'c1', mentioned: false)
          .incremented('s1', 'c2', mentioned: false);
      expect(state.unreadForChannel('s1', 'c1'), 2);
      expect(state.unreadForServer('s1'), 3);
    });

    test('incrementing a DM only moves the DM count', () {
      final state = const NotificationsState()
          .incremented('s1', 'c1', mentioned: false)
          .incrementedDm('s1', 'peer1')
          .incrementedDm('s1', 'peer1');
      expect(state.unreadForDm('s1', 'peer1'), 2);
      expect(state.dmUnreadForServer('s1'), 2);
      expect(state.unreadForChannel('s1', 'c1'), 1);
      expect(state.unreadForServer('s1'), 3);
    });

    test('clearing the last channel drops the server key entirely', () {
      final state = const NotificationsState()
          .incremented('s1', 'c1', mentioned: false)
          .clearedChannel('s1', 'c1');
      expect(state.unreadByServer.containsKey('s1'), isFalse);
    });

    test('clearing the last conversation drops the server key entirely', () {
      final state = const NotificationsState()
          .incrementedDm('s1', 'peer1')
          .clearedDm('s1', 'peer1');
      expect(state.dmUnreadByServer.containsKey('s1'), isFalse);
    });

    test('clearing a channel leaves its siblings alone', () {
      final state = const NotificationsState()
          .incremented('s1', 'c1', mentioned: false)
          .incremented('s1', 'c2', mentioned: false)
          .clearedChannel('s1', 'c1');
      expect(state.unreadForChannel('s1', 'c1'), 0);
      expect(state.unreadForChannel('s1', 'c2'), 1);
    });

    test('reading a conversation leaves the channels badged', () {
      final state = const NotificationsState()
          .incremented('s1', 'c1', mentioned: false)
          .incrementedDm('s1', 'peer1')
          .clearedDm('s1', 'peer1');
      expect(state.unreadForDm('s1', 'peer1'), 0);
      expect(state.unreadForChannel('s1', 'c1'), 1);
    });

    test('clearing something already clear returns the same instance', () {
      // The cubit clears on every focus change and every message in the open
      // channel or conversation; returning `this` is what stops those from
      // emitting.
      final state = const NotificationsState()
          .incremented('s1', 'c1', mentioned: false)
          .incrementedDm('s1', 'peer1');
      expect(state.clearedChannel('s1', 'other'), same(state));
      expect(state.clearedChannel('other', 'c1'), same(state));
      expect(state.clearedDm('s1', 'other'), same(state));
      expect(state.clearedDm('other', 'peer1'), same(state));
      expect(state.clearedServer('other'), same(state));
      // A channel id is not a peer id, even on the right server.
      expect(state.clearedDm('s1', 'c1'), same(state));
    });

    test('a re-seed replaces both halves of a server wholesale', () {
      final state = const NotificationsState()
          .incremented('s1', 'stale', mentioned: false)
          .incrementedDm('s1', 'stalePeer')
          .withServerCounts(
            's1',
            channels: {'c1': 7},
            mentions: const {},
            dms: {'peer1': 2},
            channelPrefs: const {},
            dmPrefs: const {},
          );
      expect(state.unreadForChannel('s1', 'stale'), 0);
      expect(state.unreadForDm('s1', 'stalePeer'), 0);
      expect(state.unreadForChannel('s1', 'c1'), 7);
      expect(state.unreadForDm('s1', 'peer1'), 2);
    });

    test('re-seeding with nothing unread removes the server', () {
      final state = const NotificationsState()
          .incremented('s1', 'c1', mentioned: false)
          .incrementedDm('s1', 'peer1')
          .incremented('s2', 'c2', mentioned: false)
          .withServerCounts(
            's1',
            channels: const {},
            mentions: const {},
            dms: const {},
            channelPrefs: const {},
            dmPrefs: const {},
          );
      expect(state.unreadByServer.containsKey('s1'), isFalse);
      expect(state.dmUnreadByServer.containsKey('s1'), isFalse);
      expect(state.unreadForServer('s2'), 1);
    });

    test('leaving a server drops its channels and its DMs', () {
      final state = const NotificationsState()
          .incremented('s1', 'c1', mentioned: false)
          .incrementedDm('s1', 'peer1')
          .incremented('s2', 'c2', mentioned: false)
          .clearedServer('s1');
      expect(state.unreadByServer.keys, ['s2']);
      expect(state.dmUnreadByServer.keys, isEmpty);
    });

    test('marking a server read clears both halves', () {
      // What "Mark all as read" leans on.
      final state = const NotificationsState()
          .incremented('s1', 'c1', mentioned: false)
          .incrementedDm('s1', 'peer1')
          .clearedServer('s1');
      expect(state.unreadForServer('s1'), 0);
    });

    test('transforms never mutate the state they came from', () {
      final original = const NotificationsState()
          .incremented('s1', 'c1', mentioned: false)
          .incrementedDm('s1', 'peer1');
      original.incremented('s1', 'c1', mentioned: false);
      original.incrementedDm('s1', 'peer1');
      original.clearedChannel('s1', 'c1');
      original.clearedDm('s1', 'peer1');
      original.withServerCounts(
        's1',
        channels: {'c9': 9},
        mentions: const {},
        dms: {'p9': 9},
        channelPrefs: const {},
        dmPrefs: const {},
      );
      expect(original.unreadForChannel('s1', 'c1'), 1);
      expect(original.unreadForDm('s1', 'peer1'), 1);
      expect(original.unreadForServer('s1'), 2);
    });
  });

  group('NotificationsState levels', () {
    const muted = NotificationsState(
      unreadByServer: {
        's1': {'loud': 3, 'quiet': 40},
      },
      dmUnreadByServer: {
        's1': {'peer1': 2, 'peer2': 5},
      },
      channelLevels: {
        's1': {'quiet': NotificationLevel.none},
      },
      dmLevels: {
        's1': {'peer2': NotificationLevel.none},
      },
    );

    test('a scope nobody has an opinion about answers with the default', () {
      expect(
        muted.channelLevel('s1', 'loud'),
        NotificationLevel.channelDefault,
      );
      expect(muted.dmLevel('s1', 'peer1'), NotificationLevel.dmDefault);
      expect(muted.channelLevel('nope', 'nope'), NotificationLevel.mentions);
    });

    test('a muted scope keeps its own count', () {
      expect(muted.unreadForChannel('s1', 'quiet'), 40);
      expect(muted.unreadForDm('s1', 'peer2'), 5);
    });

    test('but is left out of every total that adds several together', () {
      expect(muted.unreadForServer('s1'), 5);
      expect(muted.dmUnreadForServer('s1'), 2);
      expect(muted.badgeForServer('s1'), 2);
      expect(muted.totalBadgeExcept(null), 2);
      expect(muted.totalBadgeExcept('s1'), 0);
    });

    test('setting a level does not touch the counts', () {
      final next = muted.withLevel(
        's1',
        'loud',
        NotificationLevel.none,
        isChannel: true,
      );
      expect(next.unreadForChannel('s1', 'loud'), 3);
      expect(next.unreadForServer('s1'), 2);
      // And the state it came from is untouched.
      expect(muted.unreadForServer('s1'), 5);
    });

    test('a channel level and a DM level do not collide on one id', () {
      final next = const NotificationsState()
          .withLevel('s1', 'x', NotificationLevel.none, isChannel: true)
          .withLevel('s1', 'x', NotificationLevel.all, isChannel: false);
      expect(next.channelLevel('s1', 'x'), NotificationLevel.none);
      expect(next.dmLevel('s1', 'x'), NotificationLevel.all);
    });

    test('leaving a server drops its levels too', () {
      final next = muted.clearedServer('s1');
      expect(
        next.channelLevel('s1', 'quiet'),
        NotificationLevel.channelDefault,
      );
      expect(next.dmLevel('s1', 'peer2'), NotificationLevel.dmDefault);
    });
  });

  group('NotificationsState server level', () {
    const state = NotificationsState(
      unreadByServer: {
        's1': {'loud': 3, 'ordinary': 7},
      },
      dmUnreadByServer: {
        's1': {'peer1': 2},
      },
      serverLevels: {'s1': NotificationLevel.none},
      channelLevels: {
        's1': {'loud': NotificationLevel.all},
      },
    );

    test('a muted server answers for everything with no level of its own', () {
      expect(state.channelLevel('s1', 'ordinary'), NotificationLevel.none);
      expect(state.dmLevel('s1', 'peer1'), NotificationLevel.none);
    });

    test('a channel turned up inside it keeps what it was given', () {
      expect(state.channelLevel('s1', 'loud'), NotificationLevel.all);
    });

    test('so only the channel that was turned up counts on the outside', () {
      expect(state.unreadForServer('s1'), 3);
      expect(state.dmUnreadForServer('s1'), 0);
      expect(state.badgeForServer('s1'), 3);
      expect(state.totalBadgeExcept(null), 3);
    });

    test('every count is still its own count', () {
      expect(state.unreadForChannel('s1', 'ordinary'), 7);
      expect(state.unreadForDm('s1', 'peer1'), 2);
    });

    test('a channel set to its own default stays there when the server is '
        'turned up', () {
      // What a re-seed hands over: every stored level, the default included.
      final seeded = const NotificationsState().withServerCounts(
        's1',
        channels: const {},
        mentions: const {},
        dms: const {},
        serverPref: NotificationLevel.all,
        channelPrefs: NotificationLevel.mapFrom({
          'quiet': 'mentions',
        }, fallback: null),
        dmPrefs: const {},
      );
      expect(seeded.channelLevel('s1', 'quiet'), NotificationLevel.mentions);
      expect(seeded.channelLevel('s1', 'other'), NotificationLevel.all);
    });

    test('a server nobody has an opinion about quiets nothing', () {
      const untouched = NotificationsState(
        unreadByServer: {
          's1': {'c': 4},
        },
      );
      expect(untouched.serverLevel('s1'), NotificationLevel.serverDefault);
      expect(untouched.channelLevel('s1', 'c'), NotificationLevel.mentions);
      expect(untouched.unreadForServer('s1'), 4);
    });

    test(
      'clearing the server level puts the scopes back on their defaults',
      () {
        final next = state.withServerLevel('s1', null);
        expect(next.channelLevel('s1', 'ordinary'), NotificationLevel.mentions);
        expect(next.dmLevel('s1', 'peer1'), NotificationLevel.all);
        expect(next.channelLevel('s1', 'loud'), NotificationLevel.all);
      },
    );

    test('clearing a channel level falls back to the server again', () {
      final next = state.withoutLevel('s1', 'loud', isChannel: true);
      expect(next.channelLevel('s1', 'loud'), NotificationLevel.none);
    });

    test('clearing something that had no level changes nothing', () {
      expect(
        state.withoutLevel('s1', 'ordinary', isChannel: true),
        same(state),
      );
    });

    test('leaving a server drops its server level too', () {
      final next = state.clearedServer('s1');
      expect(next.serverLevel('s1'), NotificationLevel.serverDefault);
      expect(next.channelLevel('s1', 'ordinary'), NotificationLevel.mentions);
    });
  });

  group('NotificationsState mentions', () {
    // Found by the owner, Nov 23: a message in another server's channel at
    // "Only @mentions" put a "1" on that server though it named nobody.
    test('a plain message in a mentions-only channel badges no server', () {
      final state = const NotificationsState().incremented(
        's1',
        'c1',
        mentioned: false,
      );
      expect(state.unreadForChannel('s1', 'c1'), 1);
      expect(state.attentionForChannel('s1', 'c1'), 0);
      expect(state.badgeForServer('s1'), 0);
      expect(state.totalBadgeExcept(null), 0);
      // Still unread, so "Mark all as read" still has something to do.
      expect(state.unreadForServer('s1'), 1);
    });

    test('one naming you badges it, and counts only what named you', () {
      final state = const NotificationsState()
          .incremented('s1', 'c1', mentioned: false)
          .incremented('s1', 'c1', mentioned: true)
          .incremented('s1', 'c1', mentioned: false);
      expect(state.unreadForChannel('s1', 'c1'), 3);
      expect(state.attentionForChannel('s1', 'c1'), 1);
      expect(state.badgeForServer('s1'), 1);
    });

    test('a channel at "All" counts everything, a muted one nothing', () {
      final state = const NotificationsState()
          .withLevel('s1', 'loud', NotificationLevel.all, isChannel: true)
          .withLevel('s1', 'quiet', NotificationLevel.none, isChannel: true)
          .incremented('s1', 'loud', mentioned: false)
          .incremented('s1', 'loud', mentioned: false)
          .incremented('s1', 'quiet', mentioned: true);
      expect(state.attentionForChannel('s1', 'loud'), 2);
      expect(state.attentionForChannel('s1', 'quiet'), 0);
      expect(state.badgeForServer('s1'), 2);
    });

    test('a server turned up to "All" counts every channel under it', () {
      final state = const NotificationsState()
          .withServerLevel('s1', NotificationLevel.all)
          .incremented('s1', 'c1', mentioned: false);
      expect(state.badgeForServer('s1'), 1);
    });

    test('reading a channel clears its mentions with its count', () {
      final state = const NotificationsState()
          .incremented('s1', 'c1', mentioned: true)
          .clearedChannel('s1', 'c1');
      expect(state.mentionsByServer.containsKey('s1'), isFalse);
      expect(state.badgeForServer('s1'), 0);
    });

    test('a re-seed takes the server\'s mentions, never above the count', () {
      final state = const NotificationsState()
          .incremented('s1', 'stale', mentioned: true)
          .withServerCounts(
            's1',
            channels: {'c1': 5, 'c2': 2},
            mentions: {'c1': 1, 'c2': 9, 'gone': 3},
            dms: const {},
            channelPrefs: const {},
            dmPrefs: const {},
          );
      expect(state.mentionsByServer['s1'], {'c1': 1, 'c2': 2});
      expect(state.badgeForServer('s1'), 3);
    });

    test('a server that does not count mentions counts every unread', () {
      // Before self-host 034 the answer had no `mentions`: what the badge
      // did then is what it keeps doing there.
      final state = const NotificationsState().withServerCounts(
        's1',
        channels: {'c1': 4},
        mentions: null,
        dms: const {},
        channelPrefs: const {},
        dmPrefs: const {},
      );
      expect(state.badgeForServer('s1'), 4);
    });
  });
}
