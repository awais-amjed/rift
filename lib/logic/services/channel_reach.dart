import '../../data/classes/server_member.dart';

/// Who a message in a particular channel actually reaches.
///
/// A public channel reaches the whole server, so its audience is null and this
/// is the identity function — the roster is already the answer, and fetching a
/// few thousand ids to say "all of them" would be a page of network per channel
/// open. A private channel's audience comes from `channel_audience` (migration
/// 034), which resolves `app.channel_eligible`: seated by name, or holding a
/// role that was granted access, and not banned.
///
/// Pure and shared because the same question has three askers who must not
/// disagree — the `@` menu, the `/` menu, and the send path that decides
/// whether a line is a command. Each of them silently drops what it gets wrong:
/// a mention the trigger strips, a command the bot never reads, a plaintext row
/// nobody collects.
abstract final class ChannelReach {
  /// [members] narrowed to [audience]. Null means everybody.
  static Iterable<ServerMember> within(
    Iterable<ServerMember> members,
    Set<String>? audience,
  ) => audience == null
      ? members
      : members.where((member) => audience.contains(member.id));

  /// The bots a `/` command can reach here.
  ///
  /// A command is stored **in the clear** — the bot holds no channel key, so a
  /// sealed one could never be opened (BOTS.md §4) — but `messages_select`
  /// still asks `app.can_see_channel` first. In a private channel that is false
  /// for a bot unless a role put it there: `set_channel_members` refuses to
  /// seat one directly, so a role with `channel_role_access` is the only door.
  /// Address an unreachable one and the row is written, in the clear, and never
  /// read by anybody who wanted it.
  ///
  /// Dropping it from the list is what makes that safe rather than quiet:
  /// `BotCommands.parse` returns null for a bot it was not given, so the line
  /// goes out as an ordinary **encrypted** message instead of a plaintext one
  /// addressed to nobody. A slash that reaches no bot is just a slash.
  static List<ServerMember> botsIn(
    Iterable<ServerMember> members,
    Set<String>? audience,
  ) => [
    // Banned bots are dropped here too: `app.is_addressable_bot` refuses a
    // command sent to one, so offering it would be offering a rejected send.
    for (final member in within(members, audience))
      if (member.isBot && !member.isBanned) member,
  ];
}
