import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/read_marks.dart';

/// Reading a busy channel wrote its read cursor once per message landing, and
/// every write sent a `read` to each of the reader's devices. Now one
/// cursor is written at most once every 1.5 s, and nothing is left waiting
/// past the moment its conversation is left.
void main() {
  test('a burst is written twice: at once, and once when the time is up', () {
    fakeAsync((async) {
      final written = <String>[];
      final marks = ReadMarks<String>(
        written.add,
        now: () => async.getClock(DateTime(2026)).now(),
      );

      marks.mark('a');
      expect(written, ['a']);
      for (var i = 0; i < 20; i++) {
        async.elapse(const Duration(milliseconds: 50));
        marks.mark('a');
      }
      expect(written, ['a']);
      // Another conversation is its own.
      marks.mark('b');
      expect(written, ['a', 'b']);

      async.elapse(const Duration(milliseconds: 500));
      expect(written, ['a', 'b', 'a']);

      // Quiet long enough, and the next is written at once again.
      async.elapse(const Duration(seconds: 2));
      marks.mark('a');
      expect(written, ['a', 'b', 'a', 'a']);
    });
  });

  test('flushing writes what waits, and nothing waits after', () {
    fakeAsync((async) {
      final written = <String>[];
      final marks = ReadMarks<String>(
        written.add,
        now: () => async.getClock(DateTime(2026)).now(),
      );
      marks.mark('a');
      async.elapse(const Duration(milliseconds: 100));
      marks.mark('a');
      expect(written, ['a']);

      marks.flush();
      expect(written, ['a', 'a']);
      async.elapse(const Duration(seconds: 5));
      expect(written, ['a', 'a']);
      expect(async.pendingTimers, isEmpty);
    });
  });
}
