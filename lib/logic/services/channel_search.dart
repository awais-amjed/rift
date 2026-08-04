import '../../data/classes/channel.dart';

/// Ranking for the quick switcher's channel filter.
///
/// Pure and separate from the dialog so the ordering rules — the part that
/// decides whether "gen" finds #general before #design-general — can be
/// tested without a running app.
class ChannelSearch {
  const ChannelSearch._();

  /// Channels matching [query], best match first.
  ///
  /// An empty query returns everything unchanged, so the switcher opens
  /// showing the full list rather than nothing.
  static List<Channel> filter(List<Channel> channels, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return List.of(channels);

    final scored = <({Channel channel, int rank, int index})>[];
    for (var i = 0; i < channels.length; i++) {
      final name = channels[i].name.toLowerCase();
      final at = name.indexOf(needle);
      if (at < 0) continue;
      // A name that starts with the query beats one that merely contains it —
      // typing "gen" should land on #general, not #design-general.
      scored.add((channel: channels[i], rank: at == 0 ? 0 : 1, index: i));
    }

    scored.sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      // Ties keep the server's own channel order rather than going
      // alphabetical, so the list doesn't reshuffle as you type.
      return byRank != 0 ? byRank : a.index.compareTo(b.index);
    });

    return [for (final entry in scored) entry.channel];
  }
}
