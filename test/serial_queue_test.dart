import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/serial_queue.dart';

/// The property this exists for: two runs of a teardown-then-rebuild step must
/// never overlap. When they did, both got past the teardown, both built, and
/// only the last handle was kept — leaving the other running with nothing able
/// to stop it. That was the leave-hang in a voice channel.
void main() {
  group('SerialQueue', () {
    test('a step never starts before the previous one finishes', () async {
      final queue = SerialQueue();
      final log = <String>[];
      final first = Completer<void>();

      final a = queue.add(() async {
        log.add('a:start');
        await first.future;
        log.add('a:end');
      });
      final b = queue.add(() async {
        log.add('b:start');
        log.add('b:end');
      });

      // B was submitted while A was still in flight; it must not have run.
      await Future<void>.delayed(Duration.zero);
      expect(log, ['a:start']);

      first.complete();
      await Future.wait([a, b]);

      expect(log, ['a:start', 'a:end', 'b:start', 'b:end']);
    });

    test('steps run in the order they were submitted', () async {
      final queue = SerialQueue();
      final order = <int>[];

      final futures = [
        for (var i = 0; i < 5; i++)
          queue.add(() async {
            // Later steps finish faster; order must still hold.
            await Future<void>.delayed(Duration(milliseconds: 10 - i));
            order.add(i);
          }),
      ];
      await Future.wait(futures);

      expect(order, [0, 1, 2, 3, 4]);
    });

    test('overlapping submissions each run exactly once', () async {
      final queue = SerialQueue();
      var runs = 0;

      await Future.wait([
        for (var i = 0; i < 10; i++) queue.add(() async => runs++),
      ]);

      expect(runs, 10);
    });

    test('a failed step does not poison the ones behind it', () async {
      final queue = SerialQueue();
      final log = <String>[];

      final bad = queue.add(() async => throw StateError('boom'));
      final good = queue.add(() async => log.add('ran'));

      // The failure is reported and swallowed — awaiting it must not throw,
      // or every later mute and disconnect would inherit the error.
      await expectLater(bad, completes);
      await good;

      expect(log, ['ran']);
    });

    test('a failed step still lets the next one start', () async {
      final queue = SerialQueue();
      final log = <String>[];

      unawaited(
        queue.add(() async {
          log.add('first');
          throw StateError('boom');
        }),
      );
      await queue.add(() async => log.add('second'));

      expect(log, ['first', 'second']);
    });

    test('idle waits for everything queued so far', () async {
      final queue = SerialQueue();
      var done = false;

      unawaited(
        queue.add(() async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          done = true;
        }),
      );
      await queue.idle;

      expect(done, isTrue);
    });
  });
}
