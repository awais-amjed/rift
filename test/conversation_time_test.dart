import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/clock_time.dart';
import 'package:rift/logic/services/conversation_time.dart';

void main() {
  // A Wednesday.
  final now = DateTime(2026, 9, 16, 21, 30);

  test('a clock time is twelve-hour, with AM or PM', () {
    expect(formatClock(DateTime(2026, 9, 16, 0, 5)), '12:05 AM');
    expect(formatClock(DateTime(2026, 9, 16, 12)), '12:00 PM');
    expect(formatClock(DateTime(2026, 9, 16, 21, 30)), '9:30 PM');
  });

  test('today is a clock time', () {
    expect(
      formatConversationTime(DateTime(2026, 9, 16, 9, 24), now),
      '9:24 AM',
    );
  });

  test('this week is the weekday', () {
    expect(formatConversationTime(DateTime(2026, 9, 15, 23), now), 'Tue');
    expect(formatConversationTime(DateTime(2026, 9, 10, 8), now), 'Thu');
  });

  test('earlier this year is a date', () {
    expect(formatConversationTime(DateTime(2026, 9, 9, 8), now), 'Sep 9');
  });

  test('another year says which', () {
    expect(
      formatConversationTime(DateTime(2025, 12, 31, 8), now),
      'Dec 31, 2025',
    );
  });

  test('a single message keeps its clock time for two days, then a date', () {
    expect(
      formatMessageMoment(DateTime(2026, 9, 16, 9, 24), now),
      'Today at 9:24 AM',
    );
    expect(
      formatMessageMoment(DateTime(2026, 9, 15, 23, 5), now),
      'Yesterday at 11:05 PM',
    );
    expect(formatMessageMoment(DateTime(2026, 9, 14, 8), now), 'Sep 14');
    expect(formatMessageMoment(DateTime(2025, 12, 31, 8), now), 'Dec 31, 2025');
  });
}
