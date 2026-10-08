import 'package:equatable/equatable.dart';
import 'equality_props.dart';

/// The words of a poll — sealed into the message body, so the server never
/// reads them.
///
/// Only the words. How many options there are, whether a voter may pick
/// several, and when voting stops are the server's to enforce, so they travel
/// in the clear on the row (`messages.poll`) and are read from there — see
/// [PollRules]. The count is in both, and a message whose two counts disagree
/// is not drawn as a poll at all: see [Poll.combine].
class PollBody extends Equatable {
  static const int minOptions = 2;
  static const int maxOptions = 10;
  static const int maxQuestion = 300;
  static const int maxOption = 55;

  final String question;
  final List<String> options;

  const PollBody({required this.question, required this.options});

  Map<String, dynamic> toJson() => {'q': question, 'o': options};

  /// Read a poll out of a decoded body, or null if there is not a usable one.
  ///
  /// The sender fills these fields, so anything off-shape is no poll rather
  /// than an error: a message with a broken poll still renders its text.
  static PollBody? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final question = raw['q'];
    final options = raw['o'];
    if (question is! String || question.trim().isEmpty) return null;
    if (options is! List || options.any((o) => o is! String)) return null;
    if (options.length < minOptions || options.length > maxOptions) {
      return null;
    }
    return PollBody(question: question, options: options.cast<String>());
  }

  @override
  List<Object?> get props => [question, options];
}

/// A poll's rules as the server holds them: the option count, whether more
/// than one may be picked, and when voting stops.
///
/// `closesAt` is the moment voting stopped or will stop. Ending a poll early
/// moves it to then, so "closed" is one comparison however it got there.
class PollRules extends Equatable {
  final int options;
  final bool multiple;
  final DateTime closesAt;

  const PollRules({
    required this.options,
    required this.multiple,
    required this.closesAt,
  });

  Map<String, dynamic> toJson() => {
    'options': options,
    'multiple': multiple,
    'closes_at': closesAt.toUtc().toIso8601String(),
  };

  static PollRules? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final options = raw['options'];
    final multiple = raw['multiple'];
    final closesAt = DateTime.tryParse('${raw['closes_at']}');
    if (options is! num || multiple is! bool || closesAt == null) return null;
    return PollRules(
      options: options.toInt(),
      multiple: multiple,
      closesAt: closesAt,
    );
  }

  @override
  List<Object?> get props => [options, multiple, closesAt];
}

/// A poll as it is drawn: the sender's words, under the server's rules.
class Poll extends Equatable {
  final String question;
  final List<String> options;
  final bool multiple;
  final DateTime closesAt;

  const Poll({
    required this.question,
    required this.options,
    required this.multiple,
    required this.closesAt,
  });

  /// The two halves together, or null when they do not describe the same
  /// poll.
  ///
  /// A mismatch is a sender whose sealed words and posted rules disagree —
  /// which no Rift client produces — and counting votes against option
  /// numbers that point at different words than the reader sees would be
  /// counting the wrong thing. So it is not a poll, and the message's text is
  /// all that is drawn.
  static Poll? combine(PollBody? body, PollRules? rules) {
    if (body == null || rules == null) return null;
    if (body.options.length != rules.options) return null;
    return Poll(
      question: body.question,
      options: body.options,
      multiple: rules.multiple,
      closesAt: rules.closesAt,
    );
  }

  bool isClosedAt(DateTime now) => !now.isBefore(closesAt);

  @override
  List<Object?> get props => [question, options, multiple, closesAt];
}

/// How a poll stands: the count per option, how many people voted, and which
/// options the reader picked.
///
/// Never who else voted for what — the server does not say (`poll_tallies`).
class PollTally extends Equatable {
  final List<int> counts;
  final int voters;
  final Set<int> mine;

  const PollTally({
    required this.counts,
    required this.voters,
    this.mine = const {},
  });

  /// Nobody has voted yet. What a poll shows before its tally has arrived.
  factory PollTally.empty(int options) =>
      PollTally(counts: List.filled(options, 0), voters: 0);

  int get total => counts.fold(0, (sum, n) => sum + n);

  /// The share of [option], as a fraction of every pick. Of picks rather than
  /// of voters, so a multiple-choice poll's bars still add up to a whole.
  double shareOf(int option) {
    final all = total;
    if (all == 0 || option < 0 || option >= counts.length) return 0;
    return counts[option] / all;
  }

  static PollTally? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final counts = raw['counts'];
    if (counts is! List) return null;
    final mine = raw['mine'];
    return PollTally(
      counts: [for (final n in counts) n is num ? n.toInt() : 0],
      voters: (raw['voters'] as num?)?.toInt() ?? 0,
      mine: {
        if (mine is List)
          for (final o in mine)
            if (o is num) o.toInt(),
      },
    );
  }

  @override
  List<Object?> get props => [counts, voters, SetProp(mine)];
}
