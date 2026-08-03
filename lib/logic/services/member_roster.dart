import '../../data/classes/server_member.dart';

/// Splits a server's members into the online/offline groups the member
/// sidebar renders. Pure, so the ordering and filtering rules are stated once
/// and tested rather than re-derived in a builder.
class MemberRoster {
  const MemberRoster._();

  /// Members grouped by presence, each sorted by display name
  /// (case-insensitive). Banned members are dropped — they can't be here.
  ///
  /// [onlineIds] comes from Realtime presence, which reports *user ids only*;
  /// an id with no matching member row (a member who left, or one added since
  /// the list was fetched) is simply ignored rather than invented.
  static ({List<ServerMember> online, List<ServerMember> offline}) split(
    List<ServerMember> members,
    Set<String> onlineIds,
  ) {
    final online = <ServerMember>[];
    final offline = <ServerMember>[];
    for (final member in members) {
      if (member.isBanned) continue;
      (onlineIds.contains(member.id) ? online : offline).add(member);
    }
    online.sort(_byDisplayName);
    offline.sort(_byDisplayName);
    return (online: online, offline: offline);
  }

  static int _byDisplayName(ServerMember a, ServerMember b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
}
