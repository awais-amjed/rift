import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/watch_resume.dart';

void main() {
  const stream = 'them~d2_screenshare';
  final dropped = DateTime(2026, 10, 6, 12);

  test('a stream back within the grace is watched again', () {
    final resume = WatchResume()..remember([stream], dropped);
    expect(
      resume.take(stream, dropped.add(const Duration(seconds: 4))),
      isTrue,
    );
  });

  test('a stream back after the grace is a new decision', () {
    final resume = WatchResume()..remember([stream], dropped);
    final late = dropped.add(WatchResume.grace + const Duration(seconds: 1));
    expect(resume.take(stream, late), isFalse);
  });

  test('answers once, so a later drop has to be remembered again', () {
    final resume = WatchResume()..remember([stream], dropped);
    expect(resume.take(stream, dropped), isTrue);
    expect(resume.take(stream, dropped), isFalse);
  });

  test('a stream that was never watched is not resumed', () {
    final resume = WatchResume()..remember([stream], dropped);
    expect(resume.take('other~d3_screenshare', dropped), isFalse);
  });

  test('leaving the call forgets everything', () {
    final resume = WatchResume()
      ..remember([stream], dropped)
      ..clear();
    expect(resume.take(stream, dropped), isFalse);
  });
}
