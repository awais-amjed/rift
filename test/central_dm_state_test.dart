import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/friend.dart';
import 'package:rift/data/classes/friend_directory.dart';
import 'package:rift/data/enums/friendship_state.dart';
import 'package:rift/data/enums/notification_level.dart';
import 'package:rift/logic/cubits/central_dm/central_dm_cubit.dart';

/// What the badges say and whether the composer is open — the two things the
/// friends gate changes about a screen that was already there.
void main() {
  Friend friend(String id, FriendshipState state) =>
      Friend(id: id, handle: 'h$id', state: state);

  final graph = FriendDirectory(
    friends: [friend('u1', FriendshipState.friends)],
    incoming: [friend('u2', FriendshipState.incoming)],
    outgoing: [friend('u3', FriendshipState.outgoing)],
    blocked: [friend('u4', FriendshipState.blocked)],
  );

  final state = CentralDmState(
    status: CentralDmStatus.ready,
    graph: graph,
    unreadByPeer: const {'u1': 3, 'u2': 5, 'u3': 1, 'u4': 9},
  );

  group('the unread total', () {
    test('counts everyone but a blocked peer', () {
      // u4 is blocked: their conversation is not in the list, so unread from
      // them would be a number pointing at nothing. Everybody else counts —
      // and since the gate went in, nothing can arrive from a stranger at all.
      expect(state.totalUnread, 9); // u1's 3 + u2's 5 + u3's 1
    });

    test(
      'a muted conversation keeps its count and stops adding to the total',
      () {
        final muted = state.copyWith(
          levelsByPeer: const {'u1': NotificationLevel.none},
        );
        expect(muted.unreadByPeer['u1'], 3);
        expect(muted.totalUnread, 6);
      },
    );

    test('the Home badge adds the people waiting for an answer', () {
      // One per request, however long it has been waiting.
      expect(state.homeBadge, 10);
    });

    test('a request alone still lights the badge', () {
      // The case the badge exists for: a request carries no message, so there
      // is nothing unread anywhere and the only sign of it is this number.
      final only = CentralDmState(
        status: CentralDmStatus.ready,
        graph: FriendDirectory(
          incoming: [friend('u2', FriendshipState.incoming)],
        ),
      );
      expect(only.totalUnread, 0);
      expect(only.homeBadge, 1);
    });
  });

  group('whether the composer is open', () {
    test('nothing open is not a refusal', () {
      expect(state.canSendToOpen, isTrue);
    });

    test('only a friend can be written to', () {
      expect(state.copyWith(openPeerId: 'u1').canSendToOpen, isTrue);
      expect(state.copyWith(openPeerId: 'u2').canSendToOpen, isFalse);
      expect(state.copyWith(openPeerId: 'u3').canSendToOpen, isFalse);
      expect(state.copyWith(openPeerId: 'u4').canSendToOpen, isFalse);
    });

    test('a stranger is refused, request or no request', () {
      // The hole this replaced: a stranger used to get one message, and
      // withdrawing a request refilled it. There is nothing to spend now.
      expect(state.copyWith(openPeerId: 'u9').canSendToOpen, isFalse);
    });
  });

  group('navigating to friends', () {
    test(
      'opening friends closes the conversation and survives the same call',
      () {
        // Both arguments in one copyWith: closing must not clear the flag that
        // the same call is setting.
        final open = state.copyWith(openPeerId: 'u1');
        final friends = open.copyWith(
          closeConversation: true,
          friendsOpen: true,
        );

        expect(friends.openPeerId, isNull);
        expect(friends.friendsOpen, isTrue);
        expect(friends.chatStatus, DmChatStatus.closed);
      },
    );
  });
}
