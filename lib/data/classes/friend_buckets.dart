import '../enums/friendship_state.dart';
import 'friend.dart';
import 'paged.dart';

/// How many people are in each part of the friends graph, and the rows of
/// whichever tabs have been opened.
///
/// It replaces `FriendDirectory`, which held all four lists at once because
/// `friend_list()` returned all four at once — and that was right while three
/// of them were read from outside their own tab. Central migration 014 took
/// those jobs away: [counts] feeds the rail badge and the tab labels, and the
/// per-conversation state rides on the conversation row. What is left is three
/// lists that only their own tab reads, so a list is null until somebody looks
/// at it.
///
/// Null and empty are different on purpose. Null is "nobody has opened this
/// tab"; an empty [Paged] is "opened, and there is nobody in it". A tab that
/// drew "no friends yet" while its first page was still in flight would be
/// telling somebody something untrue about their own account.
class FriendBuckets {
  /// From `friend_counts()`. Known before any tab is opened, which is what
  /// lets the rows wait.
  final ({int friends, int incoming, int outgoing, int blocked}) counts;

  final Paged<Friend>? friends;
  final Paged<Friend>? incoming;
  final Paged<Friend>? outgoing;
  final Paged<Friend>? blocked;

  const FriendBuckets({
    this.counts = (friends: 0, incoming: 0, outgoing: 0, blocked: 0),
    this.friends,
    this.incoming,
    this.outgoing,
    this.blocked,
  });

  /// Nothing loaded — what every signed-out and still-loading frame draws
  /// from, so it has to cost nothing.
  static const FriendBuckets empty = FriendBuckets();

  /// What the Requests badge counts. Outgoing requests are not in it: waiting
  /// for an answer is not something to be notified about.
  int get requestCount => counts.incoming;

  int countOf(FriendBucket bucket) => switch (bucket) {
    FriendBucket.friends => counts.friends,
    FriendBucket.incoming => counts.incoming,
    FriendBucket.outgoing => counts.outgoing,
    FriendBucket.blocked => counts.blocked,
  };

  Paged<Friend>? pageOf(FriendBucket bucket) => switch (bucket) {
    FriendBucket.friends => friends,
    FriendBucket.incoming => incoming,
    FriendBucket.outgoing => outgoing,
    FriendBucket.blocked => blocked,
  };

  /// Where the caller stands with [peerId] **according to the rows loaded so
  /// far**, or null when no open tab mentions them.
  ///
  /// Null is the common answer and not a failure: the authoritative source for
  /// somebody you have a conversation with is that conversation's own row, and
  /// this is only the fallback for a peer reached from the friends page before
  /// any message has been exchanged with them.
  FriendshipState? stateOf(String peerId) {
    for (final entry in [
      // Blocked first, and that ordering is load-bearing. Blocking tears the
      // friendship down server-side, so the two cannot both be true — but a
      // stale page is exactly when this is read, and "blocked" is the answer
      // that fails safe.
      (blocked, FriendshipState.blocked),
      (friends, FriendshipState.friends),
      (incoming, FriendshipState.incoming),
      (outgoing, FriendshipState.outgoing),
    ]) {
      for (final friend in entry.$1?.items ?? const <Friend>[]) {
        if (friend.id == peerId) return entry.$2;
      }
    }
    return null;
  }

  FriendBuckets withPage(FriendBucket bucket, Paged<Friend>? page) =>
      FriendBuckets(
        counts: counts,
        friends: bucket == FriendBucket.friends ? page : friends,
        incoming: bucket == FriendBucket.incoming ? page : incoming,
        outgoing: bucket == FriendBucket.outgoing ? page : outgoing,
        blocked: bucket == FriendBucket.blocked ? page : blocked,
      );

  /// New counts, and every loaded page dropped.
  ///
  /// Dropped rather than kept, because a count that changed means the rows
  /// behind it did: somebody accepted, somebody blocked. Keeping a page whose
  /// count has moved is how a tab shows a request that was answered a minute
  /// ago.
  FriendBuckets withCounts(
    ({int friends, int incoming, int outgoing, int blocked}) next,
  ) => FriendBuckets(counts: next);
}

/// One list on the friends page. Named for the `friend_bucket` argument, so
/// the client and the RPC cannot drift.
///
/// Four, where the page shows three tabs: Pending holds both directions, and
/// they are fetched and labelled separately because "wants to reach you" and
/// "waiting for them" are opposite jobs.
enum FriendBucket {
  friends,
  incoming,
  outgoing,
  blocked;

  String get wire => name;
}
