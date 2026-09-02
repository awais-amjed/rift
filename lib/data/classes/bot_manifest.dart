/// What a bot says it can do, published on its own `users.manifest`
/// (migration 015, BOTS.md §4).
///
/// **Advertisement, not evidence.** Nothing here authorises anything: a client
/// renders it so `/play` can be offered without asking the bot — which matters
/// because the bot is usually asleep, and because a menu costing a round trip
/// per keystroke is not a menu. What the bot then *does* is checked by the same
/// policies as everything else.
class BotManifest {
  /// One line on what the bot is for.
  final String? description;

  /// The bot's own statement of what it does with what it is handed —
  /// "messages you send this bot are forwarded to an outside service".
  ///
  /// BOTS.md §8: for an AI bot this sentence is worth more than any amount of
  /// key management. The bot reads the command either way; what the user needs
  /// is to know that *before* typing, which is why it belongs beside the
  /// command list rather than in a settings screen.
  final String? dataUse;

  final List<BotCommandSpec> commands;

  const BotManifest({this.description, this.dataUse, this.commands = const []});

  static const empty = BotManifest();

  /// Tolerant on purpose: a manifest is written by somebody else's program, so
  /// a field of the wrong type is a field to ignore rather than a reason to
  /// render nothing.
  factory BotManifest.fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    final raw = json['commands'];
    return BotManifest(
      description: json['description'] as String?,
      dataUse: json['data_use'] as String?,
      commands: raw is! List
          ? const []
          : [
              for (final c in raw)
                if (c is Map<String, dynamic> && c['name'] is String)
                  BotCommandSpec.fromJson(c),
            ],
    );
  }

  Map<String, dynamic> toJson() => {
    if (description != null) 'description': description,
    if (dataUse != null) 'data_use': dataUse,
    'commands': [for (final c in commands) c.toJson()],
  };
}

/// One verb a bot answers to.
class BotCommandSpec {
  /// The word after the slash, without it. Lower-cased on the way in so
  /// `/Play` and `/play` are the same command.
  final String name;
  final String? description;

  /// How to call it — `<song>`, `<user> [reason]`. Shown beside the name so
  /// the picker can say what a command wants without the bot being reachable.
  final String? usage;

  /// Whether sending this command should call the bot into the sender's call.
  ///
  /// **Rift knows no verb names.** `/play` is not special and neither is
  /// `/disconnect`; the bot's author says which of its commands mean this, and
  /// a bot with none is simply never summoned by typing. That is what keeps
  /// every command from dragging a program into whatever call the sender
  /// happens to be sitting in — sealing a media key and adding a speaker for a
  /// dice roll.
  ///
  /// Advertisement like the rest of the manifest: the summon it triggers is
  /// checked against `SUMMON_BOTS` and is publish-only regardless, so a bot
  /// that lies here gains a speaker's seat and nothing else.
  final bool summonsBot;

  /// Whether sending it should send the bot out of that call.
  ///
  /// The mirror, and the reason it is the *client* that acts on it: leaving
  /// then does not depend on the bot doing anything. A bot that crashed
  /// mid-track, or one that ignores the verb it advertised, still loses its
  /// media key and its connection — the same thing "Send away" does from the
  /// participant menu, reachable by typing.
  ///
  /// Separate from stopping whatever the bot is doing, which is the bot's own
  /// business and needs no flag: a `/stop` that ends the track and stays for
  /// the next one is an ordinary command.
  final bool dismissesBot;

  const BotCommandSpec({
    required this.name,
    this.description,
    this.usage,
    this.summonsBot = false,
    this.dismissesBot = false,
  });

  factory BotCommandSpec.fromJson(Map<String, dynamic> json) => BotCommandSpec(
    name: (json['name'] as String).toLowerCase(),
    description: json['description'] as String?,
    usage: json['usage'] as String?,
    summonsBot: json['summon'] == true,
    dismissesBot: json['dismiss'] == true,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    if (usage != null) 'usage': usage,
    if (summonsBot) 'summon': true,
    if (dismissesBot) 'dismiss': true,
  };
}
