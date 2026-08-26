import '../../data/classes/server_member.dart';

/// Splits a server's roster into the groups the member sidebar renders. Pure,
/// so the ordering and filtering rules are stated once and tested rather than
/// re-derived in a builder.
class MemberRoster {
  const MemberRoster._();

  /// Bots, then members grouped by presence, each sorted by display name
  /// (case-insensitive). Banned members are dropped — they can't be here.
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
  /// [onlineIds] comes from Realtime presence, which reports *user ids only*;
  /// an id with no matching member row (a member who left, or one added since
  /// the list was fetched) is simply ignored rather than invented.
  static ({
    List<ServerMember> bots,
    List<ServerMember> online,
    List<ServerMember> offline,
  })
  split(List<ServerMember> members, Set<String> onlineIds) {
    final bots = <ServerMember>[];
    final online = <ServerMember>[];
    final offline = <ServerMember>[];
    for (final member in members) {
      if (member.isBanned) continue;
      if (member.isBot) {
        bots.add(member);
      } else {
        (onlineIds.contains(member.id) ? online : offline).add(member);
      }
    }
    bots.sort(_byDisplayName);
    online.sort(_byDisplayName);
    offline.sort(_byDisplayName);
    return (bots: bots, online: online, offline: offline);
  }

  static int _byDisplayName(ServerMember a, ServerMember b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
}
