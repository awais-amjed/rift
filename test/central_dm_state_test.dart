import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/dm_conversation.dart';
import 'package:rift/data/classes/friend.dart';
import 'package:rift/data/classes/friend_buckets.dart';
import 'package:rift/data/classes/paged.dart';
import 'package:rift/data/enums/friendship_state.dart';
import 'package:rift/data/enums/notification_level.dart';
import 'package:rift/logic/cubits/central_dm/central_dm_cubit.dart';

/// What the badges say and whether the composer is open — the two things the
/// friends gate changes about a screen that was already there.
void main() {
  Friend friend(String id, FriendshipState state) =>
      Friend(id: id, handle: 'h$id', state: state);

  /// A conversation carrying the state the server resolved for it — which is
  /// where `stateFor` reads it from since central migration 014.
  DmConversation conversation(String id, FriendshipState state) =>
      DmConversation(peerId: id, peerName: 'h$id', state: state);

  final state = CentralDmState(
    status: CentralDmStatus.ready,
    conversations: [
      conversation('u1', FriendshipState.friends),
      conversation('u2', FriendshipState.incoming),
      conversation('u3', FriendshipState.outgoing),
    ],
    friends: FriendBuckets.empty.withCounts((
      friends: 1,
      incoming: 1,
      outgoing: 1,
      blocked: 1,
    )),
    unreadByPeer: const {'u1': 3, 'u2': 5, 'u3': 1},
  );

  group('the unread total', () {
    test('counts everybody in the list', () {
      // There is no blocked clause any more: `dm_conversations` leaves a
      // blocked peer out of the list, so their unread count never arrives to
      // be skipped. Since the gate went in nothing can arrive from a stranger
      // either, so what is left is simply everybody.
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
        friends: FriendBuckets.empty.withCounts((
          friends: 0,
          incoming: 1,
          outgoing: 0,
          blocked: 0,
        )),
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
    });

    test('a peer reached from the friends page, before any message', () {
      // The fallback the loaded tabs exist for: opening a chat from the
      // Friends list means there is no conversation row yet to carry the
      // state, and refusing the composer there would be refusing a friend.
      final fromTab = state.copyWith(
        conversations: const [],
        friends: FriendBuckets.empty.withPage(
          FriendBucket.friends,
          Paged<Friend>(
            items: [friend('u7', FriendshipState.friends)],
            hasMore: false,
          ),
        ),
      );

      expect(fromTab.copyWith(openPeerId: 'u7').canSendToOpen, isTrue);
      expect(fromTab.copyWith(openPeerId: 'u9').canSendToOpen, isFalse);
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
