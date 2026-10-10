import 'package:equatable/equatable.dart';

/// One row a bot offers while its command is typed (WIRE.md §7).
///
/// Picking it sends `/<command> <value>`; [label] is only what the row says.
class BotSuggestion extends Equatable {
  final String label;
  final String value;

  const BotSuggestion({required this.label, required this.value});

  /// Most a bot may offer at once, and so most a menu shows.
  static const int maxPerAnswer = 10;

  /// The rows of a `bot_suggestions` answer, or null when it is not the
  /// answer to request [id] from [botId].
  ///
  /// The id is what makes the answer trustworthy: only the bot hears the
  /// request, so only the bot knows it. Anybody else on the server may send
  /// to this person's topic, and an answer naming another id — or none — is
  /// theirs, not the bot's. A malformed row is dropped rather than the whole
  /// answer, and a value with a line break is malformed: it would send a
  /// second line nobody picked.
  static List<BotSuggestion>? fromAnswer(
    Map<String, dynamic> payload, {
    required String id,
    required String botId,
  }) {
    if (payload['v'] != 1 || payload['id'] != id || payload['bot'] != botId) {
      return null;
    }
    final items = payload['items'];
    if (items is! List) return null;
    return [
      for (final item in items.take(maxPerAnswer))
        if (item is Map &&
            item['label'] is String &&
            item['value'] is String &&
            (item['label'] as String).trim().isNotEmpty &&
            (item['value'] as String).trim().isNotEmpty &&
            (item['label'] as String).length <= 100 &&
            (item['value'] as String).length <= 500 &&
            !(item['value'] as String).contains('\n'))
          BotSuggestion(
            label: item['label'] as String,
            value: (item['value'] as String).trim(),
          ),
    ];
  }

  @override
  List<Object?> get props => [label, value];
}
