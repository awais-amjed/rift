import '../../data/classes/server_member.dart';

/// A composer line that resolved to a command for a particular bot.
class BotCommand {
  /// The bot the message will be addressed to (`messages.to_bot`).
  final ServerMember bot;

  /// The whole line, slash included, exactly as typed. It is what gets stored
  /// and what the bot parses — the client does not split arguments, because
  /// the client does not know what any command's arguments mean.
  final String text;

  /// Whether the bot declared this verb as one that calls it into the sender's
  /// call. False when the command resolved by the bot's own name, which carries
  /// no manifest entry to read it from.
  final bool summonsBot;

  /// And whether it declared the opposite — see [BotCommandSpec.dismissesBot].
  final bool dismissesBot;

  const BotCommand({
    required this.bot,
    required this.text,
    this.summonsBot = false,
    this.dismissesBot = false,
  });
}

/// Deciding whether a line the user typed is a command, and whose.
///
/// Pure, and separate from the composer, because the answer decides whether a
/// message is **encrypted or not**. That is not a rendering detail, and it
/// should be statable and testable without a widget in the room.
class BotCommands {
  const BotCommands._();

  /// Resolve [text] against the bots present, or null if it is not a command.
  ///
  /// Two spellings, both starting with `/`:
  ///
  ///   * `/play a song` — the first word is a command some bot declared;
  ///   * `/musicbot play a song` — the first word is a bot's username, for a
  ///     bot with no manifest, or when two bots declare the same verb.
  ///
  /// **Anything unrecognised is not a command**, and that is the important
  /// half. `/shrug`, `/usr/share/doc`, or a half-typed `/pl` must go out
  /// encrypted like any other message. A slash that fell through to plaintext
  /// because nothing matched would be the exact failure this design exists to
  /// prevent — and it would look like a typo, not a leak.
  static BotCommand? parse(String text, List<ServerMember> bots) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('/') || trimmed.length < 2) return null;

    final firstBreak = trimmed.indexOf(RegExp(r'\s'));
    final head =
        (firstBreak == -1
                ? trimmed.substring(1)
                : trimmed.substring(1, firstBreak))
            .toLowerCase();
    if (head.isEmpty) return null;

    // A declared verb wins. Iteration order is the roster's, which the sidebar
    // has already sorted by display name — so two bots claiming `/play`
    // resolve the same way every time rather than by whoever loaded first.
    for (final bot in bots) {
      for (final spec in bot.manifest.commands) {
        if (spec.name != head) continue;
        return BotCommand(
          bot: bot,
          text: trimmed,
          summonsBot: spec.summonsBot,
          dismissesBot: spec.dismissesBot,
        );
      }
    }

    // Then a bot's own name, which always works — including for a bot that has
    // published nothing, which is every bot until somebody writes an SDK.
    for (final bot in bots) {
      if (bot.username.toLowerCase() == head) {
        return BotCommand(bot: bot, text: trimmed);
      }
    }

    return null;
  }

  /// Whether [text] is a whole command that takes nothing after it: `/stop`
  /// typed out in full, for a verb whose manifest gives no usage.
  ///
  /// Enter sends such a line rather than completing it. Completing would only
  /// add a space, so the press looked like it did nothing. A fragment (`/st`),
  /// a verb that wants arguments (`/play <song>`) and a bot's bare name still
  /// complete first, because what Enter would send then is not what was meant.
  /// The verb resolves to the same bot [parse] would pick.
  static bool isReadyToSend(String text, List<ServerMember> bots) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('/') || trimmed.contains(RegExp(r'\s'))) {
      return false;
    }
    final name = trimmed.substring(1).toLowerCase();
    for (final bot in bots) {
      for (final spec in bot.manifest.commands) {
        if (spec.name != name) continue;
        return spec.usage == null || spec.usage!.trim().isEmpty;
      }
    }
    return false;
  }

  /// What to ask a bot for while [text] is typed, or null when there is
  /// nothing to ask: the line must be a verb the bot declared with
  /// `suggest`, a space, and something after it.
  ///
  /// By verb only, never by a bot's own name: `/musicbot play x` carries no
  /// manifest entry to have switched suggestions on.
  static ({ServerMember bot, String command, String query})? suggestionQuery(
    String text,
    List<ServerMember> bots,
  ) {
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith('/')) return null;
    final firstBreak = trimmed.indexOf(RegExp(r'\s'));
    if (firstBreak == -1) return null;
    final query = trimmed.substring(firstBreak + 1).trim();
    // WIRE.md §7 caps what is asked about; a line longer than that is not
    // somebody looking for a song.
    if (query.isEmpty || query.length > 200) return null;
    final head = trimmed.substring(1, firstBreak).toLowerCase();
    for (final bot in bots) {
      for (final spec in bot.manifest.commands) {
        if (spec.name != head) continue;
        // The first bot to declare the verb is the one [parse] sends to, so
        // it is the one to ask — even when it does not offer suggestions.
        return spec.suggests ? (bot: bot, command: head, query: query) : null;
      }
    }
    return null;
  }

  /// The commands to offer for [text], as a `/` menu.
  ///
  /// Returns every bot's every command when nothing has been typed past the
  /// slash, then narrows by prefix. A bot with no manifest still appears —
  /// under its own name — because a bot you cannot call is worse than a menu
  /// entry with no description.
  static List<({ServerMember bot, String name, String? description})> suggest(
    String text,
    List<ServerMember> bots,
  ) {
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith('/')) return const [];
    final firstBreak = trimmed.indexOf(RegExp(r'\s'));
    // Once there is a space the verb is settled and the user is typing
    // arguments; a menu that kept filtering on those would be offering to
    // replace what they are in the middle of writing.
    if (firstBreak != -1) return const [];

    final prefix = trimmed.substring(1).toLowerCase();
    final out = <({ServerMember bot, String name, String? description})>[];
    for (final bot in bots) {
      if (bot.manifest.commands.isEmpty) {
        if (bot.username.toLowerCase().startsWith(prefix)) {
          out.add((
            bot: bot,
            name: bot.username,
            description: bot.manifest.description,
          ));
        }
        continue;
      }
      for (final c in bot.manifest.commands) {
        if (!c.name.startsWith(prefix)) continue;
        out.add((bot: bot, name: c.name, description: c.description));
      }
    }
    return out;
  }
}
