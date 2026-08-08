import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/level_throttle.dart';

void main() {
  group('LevelThrottle', () {
    final start = DateTime(2026);

    test('publishes the first level immediately', () {
      // A meter should light up on the first frame, not after a blank interval.
      expect(LevelThrottle().add(0.4, start), 0.4);
    });

    test('withholds levels until the interval has passed', () {
      final throttle = LevelThrottle(
        interval: const Duration(milliseconds: 50),
      );
      throttle.add(0.4, start);

      expect(
        throttle.add(0.5, start.add(const Duration(milliseconds: 10))),
        isNull,
      );
      expect(
        throttle.add(0.5, start.add(const Duration(milliseconds: 49))),
        isNull,
      );
      expect(
        throttle.add(0.5, start.add(const Duration(milliseconds: 50))),
        isNotNull,
      );
    });

    test('carries the loudest withheld level forward', () {
      // The point of the class: a clap between two ticks must still show.
      final throttle = LevelThrottle(
        interval: const Duration(milliseconds: 50),
      );
      throttle.add(0.1, start);

      throttle.add(0.9, start.add(const Duration(milliseconds: 10)));
      throttle.add(0.2, start.add(const Duration(milliseconds: 20)));

      expect(
        throttle.add(0.2, start.add(const Duration(milliseconds: 60))),
        0.9,
      );
    });

    test(
      'starts each interval from silence rather than decaying from the last peak',
      () {
        // Otherwise a single loud frame would hold the meter up forever.
        final throttle = LevelThrottle(
          interval: const Duration(milliseconds: 50),
        );
        throttle.add(0.9, start);
        throttle.add(0.9, start.add(const Duration(milliseconds: 50)));

        expect(
          throttle.add(0.1, start.add(const Duration(milliseconds: 100))),
          0.1,
        );
      },
    );

    test('reset makes the next level publish immediately', () {
      final throttle = LevelThrottle(
        interval: const Duration(milliseconds: 50),
      );
      throttle.add(0.9, start);
      expect(
        throttle.add(0.3, start.add(const Duration(milliseconds: 10))),
        isNull,
      );

      throttle.reset();

      expect(
        throttle.add(0.3, start.add(const Duration(milliseconds: 11))),
        0.3,
      );
    });

    test(
      'reset drops the pending peak so a stale spike cannot leak into the next run',
      () {
        final throttle = LevelThrottle(
          interval: const Duration(milliseconds: 50),
        );
        throttle.add(0.1, start);
        throttle.add(0.9, start.add(const Duration(milliseconds: 10)));

        throttle.reset();

        expect(
          throttle.add(0.2, start.add(const Duration(milliseconds: 20))),
          0.2,
        );
      },
    );
  });
}
