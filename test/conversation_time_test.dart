import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/conversation_time.dart';

void main() {
  // A Wednesday.
  final now = DateTime(2026, 9, 16, 21, 30);

  test('today is a clock time', () {
    expect(formatConversationTime(DateTime(2026, 9, 16, 9, 24), now), '09:24');
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
      'Today at 09:24',
    );
    expect(
      formatMessageMoment(DateTime(2026, 9, 15, 23, 5), now),
      'Yesterday at 23:05',
    );
    expect(formatMessageMoment(DateTime(2026, 9, 14, 8), now), 'Sep 14');
    expect(formatMessageMoment(DateTime(2025, 12, 31, 8), now), 'Dec 31, 2025');
  });
}
