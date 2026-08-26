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

  const BotCommandSpec({required this.name, this.description, this.usage});

  factory BotCommandSpec.fromJson(Map<String, dynamic> json) => BotCommandSpec(
    name: (json['name'] as String).toLowerCase(),
    description: json['description'] as String?,
    usage: json['usage'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    if (usage != null) 'usage': usage,
  };
}
