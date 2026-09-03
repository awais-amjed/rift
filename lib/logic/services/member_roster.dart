import '../../data/classes/server_member.dart';

/// Splits what the client knows about a server's members into the groups the
/// member sidebar renders. Pure, so the ordering and filtering rules are stated
/// once and tested rather than re-derived in a builder.
class MemberRoster {
  const MemberRoster._();

  /// Bots, then people grouped by presence.
  ///
  /// **Bots are a group, not a badge** (BOTS.md §9). Discord lists them among
  /// the members with a small tag; here the separation is structural, because
  /// the difference is: a bot cannot be handed a channel key, hears only what
  /// it is told, and is a program somebody runs rather than a person in the
  /// room. Sorting it next to the people it cannot hear would make that a
  /// detail rather than the shape of the thing.
  ///
  /// They are *not* split by presence, but each one still knows whether it is
  /// connected — for a bot that question is "is it running", which belongs on
  /// the row and not in the grouping.
  ///
  /// The two sources for people are not interchangeable, which is why they
  /// arrive separately (migration 039):
  ///
  ///  * [known] is whoever the client has resolved **by id** — Realtime
  ///    presence, a call's participants, an author in the scrollback. It is
  ///    where the online group comes from, and it is bounded by who is actually
  ///    about rather than by how many have ever joined.
  ///  * [people] is the alphabetical roster **as far as it has been paged in**.
  ///    Somebody further down it than the reader has scrolled is simply not
  ///    here yet, which is the point: the offline group is a window, and the
  ///    header's count comes from the database rather than from its length.
  ///
  /// Somebody online is drawn once, in Online, whichever list they came from.
  /// [onlineIds] comes from Realtime presence, which reports *user ids only*;
  /// an id we cannot name yet is ignored rather than invented — their row
  /// appears when [ServerMembersCubit.resolve] lands.
  ///
  /// Banned members are dropped throughout — they can't be here.
  static ({
    List<ServerMember> bots,
    List<ServerMember> online,
    List<ServerMember> offline,
  })
  split({
    required List<ServerMember> bots,
    required Iterable<ServerMember> known,
    required List<ServerMember> people,
    required Set<String> onlineIds,
  }) {
    final onlineById = <String, ServerMember>{};
    final offline = <ServerMember>[];

    for (final member in [...known, ...people]) {
      if (member.isBanned || member.isBot) continue;
      if (onlineIds.contains(member.id)) onlineById[member.id] = member;
    }
    // Offline is drawn from the paged list alone. Somebody resolved by id but
    // never paged in is not a row anybody scrolled to — putting them in would
    // wedge a name into the middle of an alphabet at whatever moment they
    // happened to be looked up.
    for (final member in people) {
      if (member.isBanned || member.isBot) continue;
      if (!onlineIds.contains(member.id)) offline.add(member);
    }

    final visibleBots = [
      for (final bot in bots)
        if (!bot.isBanned) bot,
    ];
    visibleBots.sort(_byDisplayName);
    final online = onlineById.values.toList()..sort(_byDisplayName);
    // `people` already arrives in this order from `list_members`; sorting it
    // again is a no-op that keeps the one rule in one place.
    offline.sort(_byDisplayName);

    return (bots: visibleBots, online: online, offline: offline);
  }

  static int _byDisplayName(ServerMember a, ServerMember b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
}
