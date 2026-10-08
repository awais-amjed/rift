import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/enums/time_out_length.dart';
import 'package:rift/logic/services/time_out_label.dart';

void main() {
  final now = DateTime(2026, 9, 27, 10, 0);

  group('timeOutEndLabel', () {
    test('today is the time alone', () {
      expect(
        timeOutEndLabel(DateTime(2026, 9, 27, 18, 5), now: now),
        '6:05 PM',
      );
    });

    test('tomorrow says so', () {
      expect(
        timeOutEndLabel(DateTime(2026, 9, 28, 9, 30), now: now),
        'tomorrow 9:30 AM',
      );
    });

    test('within the week is the weekday', () {
      // 1 October 2026 is a Thursday.
      expect(
        timeOutEndLabel(DateTime(2026, 10, 1, 12, 0), now: now),
        'Thursday 12:00 PM',
      );
    });

    test('further off is the date', () {
      expect(
        timeOutEndLabel(DateTime(2026, 10, 20, 8, 0), now: now),
        'Oct 20, 8:00 AM',
      );
    });
  });

  test('every offered length is one the server accepts (28 days at most)', () {
    for (final length in TimeOutLength.values) {
      expect(length.duration.inMinutes, greaterThan(0));
      expect(length.duration.inMinutes, lessThanOrEqualTo(28 * 24 * 60));
    }
  });
}
