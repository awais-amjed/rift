/// Where the caller stands with one other central account.
///
/// The five values the central `friendship_state()` RPC answers with, spelled
/// the same way on both sides so a state can be carried from the server to a
/// widget without translation.
///
/// There is deliberately no "they blocked me". A block is invisible from the
/// side it lands on (central migration 012) — being told costs the blocker
/// their peace and gains the blocked person a reason to make a second account
/// — so from there it reads as [none] that happens to refuse.
enum FriendshipState {
  /// Strangers. Nothing can be sent; a friend request is the only opening
  /// move, and on this tier it carries no message with it.
  none,

  /// They asked. Waiting on an answer from us, with nothing attached to read.
  incoming,

  /// We asked. Waiting on them, and until they answer there is nothing to do
  /// but withdraw.
  outgoing,

  friends,

  /// We blocked them.
  blocked;

  static const _byName = {
    'none': FriendshipState.none,
    'incoming': FriendshipState.incoming,
    'outgoing': FriendshipState.outgoing,
    'friends': FriendshipState.friends,
    'blocked': FriendshipState.blocked,
  };

  /// Anything unrecognised reads as [none] — the state with the fewest
  /// assumptions in it, and the one an older client can act on safely.
  static FriendshipState parse(Object? raw) =>
      _byName[raw is String ? raw : ''] ?? FriendshipState.none;

  String toJson() => name;

  /// Whether the composer exists at all.
  ///
  /// One value, and that is the whole gate: `send_dm` refuses everything
  /// between accounts that are not friends, so a client that opened the
  /// composer anywhere else would only be collecting text for the server to
  /// bounce.
  bool get canSend => this == FriendshipState.friends;

  /// Whether this is somebody waiting for an answer from us.
  bool get isRequest => this == FriendshipState.incoming;
}
