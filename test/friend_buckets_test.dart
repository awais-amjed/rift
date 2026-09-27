import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/friend.dart';
import 'package:rift/data/classes/friend_buckets.dart';
import 'package:rift/data/classes/paged.dart';
import 'package:rift/data/enums/friendship_state.dart';

/// The client half of the friends gate, now that the rows arrive a tab at a
/// time.
///
/// What used to live here — "which conversations are worth showing" — has gone
/// to the database, where the filter is on the same side of the page boundary
/// as the paging. `policies_test.sql` §8 and §9 assert it there. What is left
/// on this side is the counts, the per-tab pages, and the fallback that names
/// somebody reached from the friends page before any message exists.
void main() {
  Friend friend(String id, String handle, FriendshipState state) =>
      Friend(id: id, handle: handle, state: state);

  Paged<Friend> page(List<Friend> items, {bool hasMore = false}) =>
      Paged<Friend>(items: items, hasMore: hasMore);

  group('what has been loaded', () {
    test('nothing is loaded to begin with, and that is not empty', () {
      // The distinction the tabs draw a spinner from: null is "nobody has
      // opened this", an empty page is "opened, and there is nobody in it".
      const buckets = FriendBuckets.empty;
      for (final bucket in FriendBucket.values) {
        expect(buckets.pageOf(bucket), isNull, reason: bucket.name);
        expect(buckets.countOf(bucket), 0, reason: bucket.name);
      }
    });

    test('a page lands on its own bucket and no other', () {
      final buckets = FriendBuckets.empty.withPage(
        FriendBucket.incoming,
        page([friend('u2', 'bo', FriendshipState.incoming)]),
      );

      expect(buckets.incoming!.items.single.handle, 'bo');
      expect(buckets.friends, isNull);
      expect(buckets.blocked, isNull);
    });

    test('new counts drop every loaded page', () {
      // A count that moved means the rows behind it did — somebody accepted,
      // somebody blocked. Keeping the page is how a tab shows a request that
      // was answered a minute ago.
      final loaded = FriendBuckets.empty.withPage(
        FriendBucket.friends,
        page([friend('u1', 'ana', FriendshipState.friends)]),
      );

      final after = loaded.withCounts((
        friends: 2,
        incoming: 1,
        outgoing: 0,
        blocked: 0,
      ));
      expect(after.friends, isNull);
      expect(after.counts.friends, 2);
    });
  });

  group('the counts', () {
    final buckets = FriendBuckets.empty.withCounts((
      friends: 3,
      incoming: 2,
      outgoing: 5,
      blocked: 1,
    ));

    test('answer per bucket', () {
      expect(buckets.countOf(FriendBucket.friends), 3);
      expect(buckets.countOf(FriendBucket.outgoing), 5);
      expect(buckets.countOf(FriendBucket.blocked), 1);
    });

    test('the request badge is incoming only', () {
      // Waiting for an answer is not something to be notified about, so the
      // five outgoing requests are not in the number on the rail.
      expect(buckets.requestCount, 2);
    });
  });

  group('naming somebody from an open tab', () {
    test('a peer in a loaded bucket has that bucket state', () {
      final buckets = FriendBuckets.empty
          .withPage(
            FriendBucket.friends,
            page([friend('u1', 'ana', FriendshipState.friends)]),
          )
          .withPage(
            FriendBucket.blocked,
            page([friend('u4', 'dex', FriendshipState.blocked)]),
          );

      expect(buckets.stateOf('u1'), FriendshipState.friends);
      expect(buckets.stateOf('u4'), FriendshipState.blocked);
    });

    test('a peer no open tab mentions is null, not a stranger', () {
      // Null and "none" are different answers. Null means nothing here knows;
      // the conversation row is asked first and it is the one that does.
      expect(FriendBuckets.empty.stateOf('u9'), isNull);
    });

    test('blocked wins over a stale bucket it also appears in', () {
      // Blocking tears the friendship down server-side, so the two cannot both
      // be true — but a stale page is exactly when this is read, and "blocked"
      // is the answer that fails safe.
      final buckets = FriendBuckets.empty
          .withPage(
            FriendBucket.friends,
            page([friend('u1', 'ana', FriendshipState.friends)]),
          )
          .withPage(
            FriendBucket.blocked,
            page([friend('u1', 'ana', FriendshipState.blocked)]),
          );

      expect(buckets.stateOf('u1'), FriendshipState.blocked);
    });
  });

  test('a friend converts to the shape a conversation opens with', () {
    const friend = Friend(
      id: 'u1',
      handle: 'ana',
      chatPublicKey: 'chat-u1',
      signingPublicKey: 'sign-u1',
      state: FriendshipState.friends,
    );
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
