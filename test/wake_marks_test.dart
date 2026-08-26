import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/push_wake/wake_marks.dart';

/// The high-water mark that stops a wake re-announcing what the last one said.
///
/// It is the only state the push isolate carries between wakes, and getting it
/// wrong is either a repeated notification or a missed one.
void main() {
  test('nothing has been announced to start with', () {
    final marks = WakeMarks({});
    expect(marks['channel:a'], 0);
    expect(marks.isFresh('channel:a', 1), isTrue);
  });

  test('a marked message is no longer fresh, and neither is an older one', () {
    final marks = WakeMarks({})..mark('channel:a', 42);
    expect(marks.isFresh('channel:a', 42), isFalse);
    expect(marks.isFresh('channel:a', 41), isFalse);
    expect(marks.isFresh('channel:a', 43), isTrue);
  });

  test('marks are per conversation', () {
    final marks = WakeMarks({})..mark('channel:a', 42);
    expect(marks.isFresh('channel:b', 1), isTrue);
  });

  test('a mark never moves backwards', () {
    final marks = WakeMarks({})
      ..mark('channel:a', 42)
      ..mark('channel:a', 7);
    expect(marks['channel:a'], 42);
  });

  test('pruning keeps the highest ids, which are the most recent', () {
    final marks = WakeMarks({
      for (var i = 0; i < WakeMarks.maxEntries + 10; i++) 'scope:$i': i,
    });
    final pruned = pruned2(marks);
    expect(pruned.length, WakeMarks.maxEntries);
    expect(pruned.containsKey('scope:9'), isFalse);
    expect(pruned.containsKey('scope:${WakeMarks.maxEntries + 9}'), isTrue);
  });

  test('a small set is left alone', () {
    final marks = WakeMarks({'a': 1, 'b': 2});
    expect(pruned2(marks), {'a': 1, 'b': 2});
  });
}

Map<String, int> pruned2(WakeMarks marks) => marks.pruned().asMap;
