import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/dm_conversation.dart';
import 'package:rift/data/classes/friend.dart';
import 'package:rift/data/classes/friend_directory.dart';
import 'package:rift/data/enums/friendship_state.dart';

/// The client half of the friends gate. Everything the sidebar and the
/// composer decide runs through this object, so a wrong answer here is a
/// stranger in the conversation list or a blocked account still on screen.
void main() {
  Map<String, dynamic> row(String id, String handle) => {
    'id': id,
    'handle': handle,
    'chat_public_key': 'chat-$id',
    'signing_public_key': 'sign-$id',
    'since': '2026-08-25T10:00:00Z',
  };

  final json = {
    'friends': [row('u1', 'ana')],
    'incoming': [row('u2', 'bo')],
    'outgoing': [row('u3', 'cy')],
    'blocked': [row('u4', 'dex')],
  };

  DmConversation conversation(String id) =>
      DmConversation(peerId: id, peerName: 'peer-$id');

  group('reading a friend_list() result', () {
    test('every bucket keeps its state and its keys', () {
      final graph = FriendDirectory.fromJson(json);

      expect(graph.friends.single.handle, 'ana');
      expect(graph.friends.single.state, FriendshipState.friends);
      // The keys travel with the row because every one of these is somewhere
      // you can start typing, and opening a conversation needs them.
      expect(graph.friends.single.chatPublicKey, 'chat-u1');
      expect(graph.friends.single.signingPublicKey, 'sign-u1');
      expect(graph.friends.single.since, DateTime.utc(2026, 8, 25, 10));

      expect(graph.incoming.single.state, FriendshipState.incoming);
      expect(graph.outgoing.single.state, FriendshipState.outgoing);
      expect(graph.blocked.single.state, FriendshipState.blocked);
    });

    test('a missing bucket is an empty one, not a crash', () {
      final graph = FriendDirectory.fromJson(const {});
      expect(graph.isEmpty, isTrue);
      expect(graph.requestCount, 0);
    });

    test('an absent person is a stranger', () {
      expect(
        FriendDirectory.fromJson(json).stateFor('nobody'),
        FriendshipState.none,
      );
      expect(const FriendDirectory.empty().stateFor('u1'),
          FriendshipState.none);
    });

    test('the request count is incoming only', () {
      // Waiting for somebody else to answer is not news, and the number here
      // has to agree with the badge on the row that opens the friends page.
      expect(FriendDirectory.fromJson(json).requestCount, 1);
    });

    test('lookup finds a person in any bucket', () {
      final graph = FriendDirectory.fromJson(json);
      expect(graph.lookup('u4')?.handle, 'dex');
      expect(graph.lookup('u9'), isNull);
    });
  });

  group('the conversations worth showing', () {
    test('everyone but a blocked peer', () {
      // There is no second list any more. A request arrives empty, so it has
      // no conversation to sit in — Pending on the friends page is where one
      // waits — and what is left here is people you agreed to hear from plus
      // whatever history survived an unfriending.
      final graph = FriendDirectory.fromJson(json);
      final visible = graph.visible([
        conversation('u1'),
        conversation('u2'),
        conversation('u3'),
        conversation('u9'),
      ]);

      expect(visible.map((c) => c.peerId), ['u1', 'u2', 'u3', 'u9']);
    });

    test('a blocked peer is left out', () {
      // Their old messages are still rows on the server — blocking takes away
      // reach and discoverability, it does not erase what was said — so this
      // is the only thing keeping them off screen.
      final visible = FriendDirectory.fromJson(json).visible([
        conversation('u4'),
        conversation('u1'),
      ]);
      expect(visible.map((c) => c.peerId), ['u1']);
    });

    test('a stranger you have history with keeps their conversation', () {
      // Somebody who unfriended you leaves the row behind, readable and not
      // addable to. Hiding it would be a deletion nobody asked for.
      final visible = FriendDirectory.fromJson(json).visible([
        conversation('u9'),
      ]);
      expect(visible.single.peerId, 'u9');
    });

    test('blocked wins over any stale bucket it also appears in', () {
      final graph = FriendDirectory(
        friends: const [
          Friend(id: 'u1', handle: 'ana', state: FriendshipState.friends),
        ],
        blocked: const [
          Friend(id: 'u1', handle: 'ana', state: FriendshipState.blocked),
        ],
      );
      expect(graph.stateFor('u1'), FriendshipState.blocked);
      expect(graph.isBlocked('u1'), isTrue);
      expect(graph.visible([conversation('u1')]), isEmpty);
    });
  });

  test('a friend converts to the shape a conversation opens with', () {
    final friend = FriendDirectory.fromJson(json).friends.single;
    final asConversation = friend.toConversation();

    expect(asConversation.peerId, 'u1');
    expect(asConversation.peerName, 'ana');
    expect(asConversation.peerChatPublicKey, 'chat-u1');
    expect(asConversation.peerSigningPublicKey, 'sign-u1');

    // And back, which is what the conversation tile's menu needs.
    final round = Friend.fromConversation(
      asConversation,
      FriendshipState.friends,
    );
    expect(round.id, friend.id);
    expect(round.handle, friend.handle);
    expect(round.chatPublicKey, friend.chatPublicKey);
    expect(round.state, FriendshipState.friends);
  });
}
