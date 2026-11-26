import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/ring_throttle.dart';

/// Any member may ring a server's `changed` and `sweep`, so a ring is
/// answered at most every two seconds, and a flood cannot hold it off
/// (security re-review, Nov 26).
void main() {
  test('a burst is one answer, once it has settled', () {
    fakeAsync((time) {
      var answers = 0;
      final throttle = RingThrottle(() => answers++);
      throttle.ring();
      throttle.ring();
      time.elapse(const Duration(milliseconds: 200));
      expect(answers, 0);
      throttle.ring();
      time.elapse(const Duration(milliseconds: 100));
      expect(answers, 1);
    });
  });

  test('a flood is answered every two seconds, and from the start', () {
    fakeAsync((time) {
      var answers = 0;
      final throttle = RingThrottle(() => answers++);
      for (var i = 0; i < 200; i++) {
        throttle.ring();
        time.elapse(const Duration(milliseconds: 50));
      }
      // Ten seconds of rings, twenty a second.
      expect(answers, inInclusiveRange(4, 6));
    });
  });

  test('a ring after a quiet spell is answered at once', () {
    fakeAsync((time) {
      var answers = 0;
      final throttle = RingThrottle(() => answers++);
      throttle.ring();
      time.elapse(const Duration(seconds: 5));
      throttle.ring();
      time.elapse(const Duration(milliseconds: 250));
      expect(answers, 2);
    });
  });

  test('cancelled, nothing is answered', () {
    fakeAsync((time) {
      var answers = 0;
      final throttle = RingThrottle(() => answers++);
      throttle.ring();
      throttle.cancel();
      time.elapse(const Duration(seconds: 3));
      expect(answers, 0);
    });
  });
}
