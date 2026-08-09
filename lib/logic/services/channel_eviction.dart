import '../../data/classes/channel.dart';

/// What a member has to let go of once the channel list has moved under them.
///
/// A deletion doesn't announce *which* channel went, and it doesn't need to:
/// after the list is refreshed, anything we are still pointed at that the
/// server no longer lists has gone — deleted, or put out of reach by a ban.
/// Treating those two the same is deliberate; the member has to leave either
/// way.
///
/// The rule lives here rather than inline because both of its edges are easy to
/// get wrong: nothing open must never count as gone, and an empty list that
/// came from a *failed* refresh would otherwise evict everyone from everything.
class ChannelEviction {
  const ChannelEviction._();

  /// The ids the server still lists.
  static Set<String> liveIds(Iterable<Channel> channels) => {
    for (final channel in channels) channel.id,
  };

  /// Whether [channelId] should be abandoned. Null — nothing open — never is.
  static bool isGone(String? channelId, Set<String> live) =>
      channelId != null && !live.contains(channelId);
}
