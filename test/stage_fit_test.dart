import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/stage_fit.dart';

void main() {
  group('stageFit', () {
    test('one person fills the width of a wide stage', () {
      final fit = stageFit(width: 800, height: 900, people: 1, streams: 0);
      expect(fit.tileWidth, 800);
    });

    test('a short stage limits by height', () {
      final fit = stageFit(width: 1600, height: 450, people: 1, streams: 0);
      expect(fit.tileWidth, closeTo(800, 1));
    });

    test('five in a tall narrow stage go two to a row, not three', () {
      // The case that made tiles tiny: three columns at 500px wide.
      final fit = stageFit(width: 500, height: 860, people: 3, streams: 2);
      expect(fit.tileWidth, greaterThan(200));
    });

    test('people are never a single column', () {
      final fit = stageFit(width: 500, height: 2000, people: 3, streams: 0);
      expect(fit.tileWidth, lessThanOrEqualTo((500 - 8) / 2));
    });

    test('a stream is a little larger than a person', () {
      final fit = stageFit(width: 1000, height: 900, people: 3, streams: 2);
      expect(fit.streamWidth, closeTo(fit.tileWidth * 1.25, 1));
    });

    test('a stream never exceeds the stage width', () {
      final fit = stageFit(width: 400, height: 2000, people: 1, streams: 1);
      expect(fit.streamWidth, lessThanOrEqualTo(400));
    });

    test('what it picks always fits', () {
      for (final (w, h, p, s) in [
        (500.0, 860.0, 3, 2),
        (1200.0, 700.0, 7, 3),
        (360.0, 640.0, 4, 1),
        (900.0, 300.0, 2, 2),
      ]) {
        final fit = stageFit(width: w, height: h, people: p, streams: s);
        double rows(int n, double tile) {
          final perRow = ((w + 8) / (tile + 8)).floor().clamp(1, 1 << 30);
          return (n / perRow).ceilToDouble();
        }

        final sr = rows(s, fit.streamWidth);
        final pr = rows(p, fit.tileWidth);
        final used =
            sr * fit.streamWidth * 9 / 16 +
            (sr - 1) * 8 +
            8 +
            pr * fit.tileWidth * 9 / 16 +
            (pr - 1) * 8;
        expect(used, lessThanOrEqualTo(h + 0.5), reason: '$w x $h');
      }
    });
    test('an unopened stream on a phone is no narrower than its least', () {
      // The phone's stage that crowded Watch onto the name: 360 wide.
      final fit = stageFit(
        width: 360,
        height: 640,
        people: 3,
        streams: 1,
        minStreamWidth: 320,
        personAspect: 4 / 3,
      );
      expect(fit.streamWidth, 320);
      expect(fit.tileWidth, (360 - 8) ~/ 2);
    });

    test('the least never goes past the stage', () {
      final fit = stageFit(
        width: 300,
        height: 900,
        people: 0,
        streams: 1,
        minStreamWidth: 320,
      );
      expect(fit.streamWidth, 300);
    });

    test('a stage too short for the least shrinks the stream again', () {
      final fit = stageFit(
        width: 360,
        height: 150,
        people: 2,
        streams: 1,
        minStreamWidth: 320,
      );
      final used = fit.streamWidth * 9 / 16 + 8 + fit.tileWidth * 9 / 16;
      expect(used, lessThanOrEqualTo(150.5));
      expect(fit.tileWidth, greaterThan(0));
    });

    test('squarer people take more height for the same width', () {
      // Tall enough for both to be held by the width alone.
      const args = (width: 360.0, height: 900.0);
      final wide = stageFit(
        width: args.width,
        height: args.height,
        people: 4,
        streams: 0,
      );
      final square = stageFit(
        width: args.width,
        height: args.height,
        people: 4,
        streams: 0,
        personAspect: 4 / 3,
      );
      expect(square.tileWidth, wide.tileWidth);
      // Short enough that 4:3 rows run out of height first.
      final short = stageFit(
        width: 360,
        height: 260,
        people: 4,
        streams: 0,
        personAspect: 4 / 3,
      );
      expect(2 * short.tileWidth * 3 / 4 + 8, lessThanOrEqualTo(260.5));
    });
  });
}
