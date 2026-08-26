import '../enums/friendship_state.dart';
import 'dm_conversation.dart';
import 'friend.dart';

/// The whole central friends graph as one value: friends, the requests waiting
/// in both directions, and the block list.
///
/// One object rather than four lists on the state for the reason `friend_list()`
/// is one RPC rather than four: everything on screen is drawn from all of them
/// at once — whether a conversation is a conversation or a request, whether the
/// composer is open, what the Requests badge says — and four fields updated
/// separately means drawing a screen from four different moments.
class FriendDirectory {
  final List<Friend> friends;
  final List<Friend> incoming;
  final List<Friend> outgoing;
  final List<Friend> blocked;

  /// peer id → state, built once. Every row of both DM lists asks this
  /// question, so it is a lookup rather than four `any` scans.
  final Map<String, FriendshipState> _states;

  FriendDirectory({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.blocked = const [],
  }) : _states = {
         for (final f in friends) f.id: FriendshipState.friends,
         for (final f in incoming) f.id: FriendshipState.incoming,
         for (final f in outgoing) f.id: FriendshipState.outgoing,
         // Last, so it wins any disagreement. Blocking tears the friendship
         // down with it server-side, so the two cannot both be true — but a
         // stale list is exactly when this is read, and "blocked" is the
         // answer that fails safe.
         for (final f in blocked) f.id: FriendshipState.blocked,
       };

  /// A graph nobody has loaded yet. `const` so the state holding it can be
  /// `const` too — the default has to cost nothing, because it is what every
  /// signed-out and still-loading frame is drawn from.
  const FriendDirectory.empty()
    : friends = const [],
      incoming = const [],
      outgoing = const [],
      blocked = const [],
      _states = const {};

  /// A `friend_list()` result: four buckets, each a list of directory rows.
  factory FriendDirectory.fromJson(Map<String, dynamic> json) {
    List<Friend> bucket(String key, FriendshipState state) => [
      for (final row in (json[key] as List? ?? const []))
        Friend.fromJson((row as Map).cast<String, dynamic>(), state: state),
    ];

    return FriendDirectory(
      friends: bucket('friends', FriendshipState.friends),
      incoming: bucket('incoming', FriendshipState.incoming),
      outgoing: bucket('outgoing', FriendshipState.outgoing),
      blocked: bucket('blocked', FriendshipState.blocked),
    );
  }

  /// Where the caller stands with [peerId]. Somebody nobody has any
  /// relationship with is simply absent, and [FriendshipState.none] answers
  /// for them.
  FriendshipState stateFor(String peerId) =>
      _states[peerId] ?? FriendshipState.none;

  bool isBlocked(String peerId) =>
      _states[peerId] == FriendshipState.blocked;

  /// What the Requests badge counts. Outgoing requests are not in it: waiting
  /// for an answer is not something to be notified about.
  int get requestCount => incoming.length;

  bool get isEmpty =>
      friends.isEmpty &&
      incoming.isEmpty &&
      outgoing.isEmpty &&
      blocked.isEmpty;

  /// The conversations worth showing, which is all of them minus the people
  /// you have blocked.
  ///
  /// There is no second list any more. A request arrives empty since central
  /// migration 012 — nothing can be sent before it is accepted — so a request
  /// has no conversation to sit in and the Requests section it used to need
  /// has become the Pending tab on the friends page.
  ///
  /// Blocked peers are left out here rather than server-side, and deliberately:
  /// their messages are still readable rows (blocking takes away reach and
  /// discoverability, it does not erase what was said), so something has to
  /// leave them out of the list, and this is it.
  List<DmConversation> visible(List<DmConversation> conversations) => [
    for (final conversation in conversations)
      if (!isBlocked(conversation.peerId)) conversation,
  ];

  Friend? lookup(String peerId) {
    for (final list in [friends, incoming, outgoing, blocked]) {
      for (final friend in list) {
        if (friend.id == peerId) return friend;
      }
    }
    return null;
  }
}
