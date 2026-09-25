import '../../data/classes/chat_message.dart';
import '../../data/classes/poll.dart';

/// Pure poll transforms: reading a poll off a decrypted row, merging tallies
/// into loaded messages, and working out the ballot a tap makes.
///
/// Tallies are counts only. Nothing here — or anywhere a member can reach —
/// knows who voted for what.
class PollOps {
  const PollOps._();

  /// Durations a poll can run for, in the order the picker offers them.
  static const durations = [
    Duration(hours: 1),
    Duration(hours: 4),
    Duration(hours: 8),
    Duration(days: 1),
    Duration(days: 3),
    Duration(days: 7),
    Duration(days: 14),
  ];

  /// The poll a decrypted row carries: its sealed [body] under the rules on
  /// the row, or null when either is missing or they disagree.
  static Poll? fromRow(Map<String, dynamic> row, PollBody? body) =>
      Poll.combine(body, PollRules.fromJson(row['poll']));

  /// Ids of the loaded polls whose tallies are worth asking for.
  static List<int> pollIds(List<ChatMessage> messages) => [
    for (final message in messages)
      if (message.poll != null && !message.isPending) ?int.tryParse(message.id),
  ];

  /// The tallies `poll_tallies` answered (`{id: {...}}`), parsed and keyed
  /// by message id, over whatever was already [known]. A poll missing from the
  /// answer keeps what it had.
  static Map<String, PollTally> mergeTallies(
    Map<String, PollTally> known,
    Map<String, dynamic> answered,
  ) => {
    ...known,
    for (final entry in answered.entries)
      entry.key: ?PollTally.fromJson(entry.value),
  };

  /// The ballot tapping [option] makes, given the options already [mine].
  ///
  /// One pick: tapping it again takes the vote back, tapping another moves
  /// it. Several: each tap toggles one option and leaves the rest.
  static List<int> ballotAfterTap({
    required bool multiple,
    required Set<int> mine,
    required int option,
  }) {
    if (!multiple) return mine.contains(option) ? const [] : [option];
    final next = {...mine};
    if (!next.remove(option)) next.add(option);
    return next.toList()..sort();
  }

  /// "4h left", "2d left", "Ended" — how long a poll has, said shortly.
  static String timeLeft(DateTime closesAt, DateTime now) {
    final left = closesAt.difference(now);
    if (left <= Duration.zero) return 'Ended';
    if (left.inDays >= 1) return '${left.inDays}d left';
    if (left.inHours >= 1) return '${left.inHours}h left';
    if (left.inMinutes >= 1) return '${left.inMinutes}m left';
    return 'Closing';
  }

  /// A duration as the picker labels it: "1 hour", "3 days", "1 week".
  static String durationLabel(Duration duration) {
    if (duration.inDays >= 7 && duration.inDays % 7 == 0) {
      final weeks = duration.inDays ~/ 7;
      return weeks == 1 ? '1 week' : '$weeks weeks';
    }
    if (duration.inDays >= 1) {
      return duration.inDays == 1 ? '1 day' : '${duration.inDays} days';
    }
    return duration.inHours == 1 ? '1 hour' : '${duration.inHours} hours';
  }

  /// The words for a refusal from `vote_poll` / `close_poll`, or null.
  static String? errorFor(String? error) {
    if (error == null) return null;
    if (error.contains('poll_closed')) return 'This poll has ended.';
    if (error.contains('poll_single_choice')) {
      return 'This poll takes one answer.';
    }
    if (error.contains('poll_not_found')) return 'This poll is gone.';
    if (error.contains('not_poll_author')) {
      return 'Only whoever posted a poll can end it.';
    }
    return null;
  }
}
