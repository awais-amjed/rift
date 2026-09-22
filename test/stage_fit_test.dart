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
        final used = sr * fit.streamWidth * 9 / 16 +
            (sr - 1) * 8 +
            8 +
            pr * fit.tileWidth * 9 / 16 +
            (pr - 1) * 8;
        expect(used, lessThanOrEqualTo(h + 0.5), reason: '$w x $h');
      }
    });
  });
}
