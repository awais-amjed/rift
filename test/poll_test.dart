import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/message_body.dart';
import 'package:rift/data/classes/poll.dart';
import 'package:rift/logic/services/poll_ops.dart';

void main() {
  final closes = DateTime.utc(2026, 9, 27, 12);
  Map<String, dynamic> rules({int options = 3, bool multiple = false}) => {
    'options': options,
    'multiple': multiple,
    'closes_at': closes.toIso8601String(),
  };
  const body = PollBody(
    question: 'Lunch?',
    options: ['Pizza', 'Sushi', 'Soup'],
  );

  group('the sealed half', () {
    test('rides in the message body and comes back out', () {
      final decoded = MessageBody.decode(
        const MessageBody(poll: body).encode(),
      );
      expect(decoded.poll?.question, 'Lunch?');
      expect(decoded.poll?.options, ['Pizza', 'Sushi', 'Soup']);
      expect(decoded.text, isEmpty);
    });

    test('a body carrying only a poll is not empty', () {
      expect(const MessageBody(poll: body).isEmpty, isFalse);
    });

    test('a malformed poll is no poll, and the text still renders', () {
      for (final raw in [
        {
          'q': '',
          'o': ['a', 'b'],
        },
        {
          'q': 'x',
          'o': ['a'],
        },
        {'q': 'x', 'o': List.filled(11, 'a')},
        {
          'q': 'x',
          'o': ['a', 3],
        },
        'not a map',
      ]) {
        expect(PollBody.fromJson(raw), isNull, reason: '$raw');
      }
    });
  });

  group('the two halves together', () {
    test('combine when the option counts agree', () {
      final poll = PollOps.fromRow({'poll': rules()}, body);
      expect(poll?.multiple, isFalse);
      expect(poll?.closesAt, closes);
    });

    test('are not a poll when the counts disagree', () {
      // Counting votes against option numbers that point at different words
      // than the reader sees would be counting the wrong thing.
      expect(PollOps.fromRow({'poll': rules(options: 4)}, body), isNull);
    });

    test('are not a poll with either half missing', () {
      expect(PollOps.fromRow({'poll': null}, body), isNull);
      expect(PollOps.fromRow({'poll': rules()}, null), isNull);
    });

    test('are closed from the closing moment on', () {
      final poll = PollOps.fromRow({'poll': rules()}, body)!;
      expect(
        poll.isClosedAt(closes.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(poll.isClosedAt(closes), isTrue);
    });
  });

  group('a tally', () {
    test('parses counts, voters and the reader\'s own picks', () {
      final tally = PollTally.fromJson({
        'counts': [1, 2, 0],
        'voters': 3,
        'mine': [1],
      })!;
      expect(tally.counts, [1, 2, 0]);
      expect(tally.voters, 3);
      expect(tally.mine, {1});
    });

    test('shares are of picks, so a multiple-choice poll still adds up', () {
      const tally = PollTally(counts: [2, 1, 1], voters: 2);
      expect(tally.shareOf(0), 0.5);
      expect(tally.shareOf(1) + tally.shareOf(2), 0.5);
    });

    test('an empty poll has no shares rather than dividing by nothing', () {
      expect(PollTally.empty(3).shareOf(0), 0);
    });

    test('merging keeps what an answer left out', () {
      const old = PollTally(counts: [1, 0], voters: 1);
      final merged = PollOps.mergeTallies(
        {'1': old, '2': old},
        {
          '2': {
            'counts': [1, 1],
            'voters': 2,
            'mine': [],
          },
        },
      );
      expect(merged['1'], same(old));
      expect(merged['2']?.voters, 2);
    });
  });

  group('a tap', () {
    test('on one pick votes, moves, and takes back', () {
      expect(PollOps.ballotAfterTap(multiple: false, mine: {}, option: 1), [1]);
      expect(PollOps.ballotAfterTap(multiple: false, mine: {1}, option: 2), [
        2,
      ]);
      expect(
        PollOps.ballotAfterTap(multiple: false, mine: {1}, option: 1),
        isEmpty,
      );
    });

    test('on several toggles one option and keeps the rest', () {
      expect(PollOps.ballotAfterTap(multiple: true, mine: {0}, option: 2), [
        0,
        2,
      ]);
      expect(PollOps.ballotAfterTap(multiple: true, mine: {0, 2}, option: 0), [
        2,
      ]);
    });
  });

  test('only acknowledged polls are asked about', () {
    ChatMessage message(String id, {bool poll = true, bool pending = false}) =>
        ChatMessage(
          id: id,
          authorId: 'a',
          authorName: 'A',
          text: '',
          sentAt: closes,
          isMine: false,
          isPending: pending,
          poll: poll ? PollOps.fromRow({'poll': rules()}, body) : null,
        );
    expect(
      PollOps.pollIds([
        message('1'),
        message('2', poll: false),
        message('pending-0', pending: true),
      ]),
      [1],
    );
  });

  test('time left reads shortly, and ends', () {
    final now = DateTime.utc(2026, 9, 26);
    expect(
      PollOps.timeLeft(now.add(const Duration(days: 2, hours: 3)), now),
      '2d left',
    );
    expect(PollOps.timeLeft(now.add(const Duration(hours: 5)), now), '5h left');
    expect(
      PollOps.timeLeft(now.add(const Duration(minutes: 9)), now),
      '9m left',
    );
    expect(PollOps.timeLeft(now, now), 'Ended');
  });

  test('every offered duration is inside the server\'s month', () {
    // `check_poll` refuses a close more than 32 days out.
    for (final duration in PollOps.durations) {
      expect(duration.inDays, lessThanOrEqualTo(32));
      expect(PollOps.durationLabel(duration), isNotEmpty);
    }
    expect(PollOps.durationLabel(const Duration(days: 14)), '2 weeks');
    expect(PollOps.durationLabel(const Duration(hours: 1)), '1 hour');
  });

  test('refusals read as sentences', () {
    expect(PollOps.errorFor('P0001: poll_closed'), 'This poll has ended.');
    expect(PollOps.errorFor('something else'), isNull);
  });
}
