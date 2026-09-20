import 'package:flutter_test/flutter_test.dart';
import 'package:rift/presentation/common/rift_mark_path.dart';

void main() {
  group('riftMarkVariantFor', () {
    test('widens the gap only where a pixel of it would be left', () {
      expect(riftMarkVariantFor(76), RiftMarkVariant.standard);
      expect(riftMarkVariantFor(32), RiftMarkVariant.standard);
      expect(riftMarkVariantFor(20), RiftMarkVariant.standard);
      expect(riftMarkVariantFor(19), RiftMarkVariant.wide);
      expect(riftMarkVariantFor(16), RiftMarkVariant.wide);
    });
  });

  group('riftMarkPath', () {
    test('stands 10 to 90 whatever the gap, inset from the sides', () {
      for (final variant in RiftMarkVariant.values) {
        final bounds = riftMarkPath(100, variant: variant).getBounds();
        expect(bounds.top, closeTo(10, 0.01), reason: '$variant crown');
        expect(bounds.bottom, closeTo(90, 0.01), reason: '$variant foot');
        expect(bounds.left, greaterThan(0), reason: '$variant');
        expect(bounds.right, lessThan(100), reason: '$variant');
        expect(
          bounds.left,
          closeTo(100 - bounds.right, 0.01),
          reason: '$variant is symmetric',
        );
      }
    });

    test('the gap is never drawn: the centre line is empty', () {
      for (final variant in RiftMarkVariant.values) {
        final path = riftMarkPath(100, variant: variant);
        for (final y in [12.0, 30.0, 50.0, 70.0, 88.0]) {
          expect(
            path.contains(Offset(50, y)),
            isFalse,
            reason: '$variant at y=$y',
          );
        }
        expect(
          path.contains(const Offset(30, 42)),
          isTrue,
          reason: '$variant upper half',
        );
        expect(
          path.contains(const Offset(70, 58)),
          isTrue,
          reason: '$variant lower half',
        );
      }
    });

    test('a half turn leaves it unchanged', () {
      // The two halves are one shape rotated about (50, 50). Mirroring one
      // instead — the easy slip, and the one that reads as two unrelated
      // shapes — fails here and nowhere else.
      for (final variant in RiftMarkVariant.values) {
        final path = riftMarkPath(100, variant: variant);
        for (var x = 5.0; x < 100; x += 7) {
          for (var y = 5.0; y < 100; y += 7) {
            expect(
              path.contains(Offset(x, y)),
              path.contains(Offset(100 - x, 100 - y)),
              reason: '$variant at ($x, $y)',
            );
          }
        }
      }
    });

    test('the halves never touch: the wide gap is wider', () {
      final standard = riftMarkPath(100, variant: RiftMarkVariant.standard);
      final wide = riftMarkPath(100, variant: RiftMarkVariant.wide);
      // A point just inside the standard gap's right edge is filled at the
      // narrow gap and clear at the wide one — the only thing the variant
      // changes.
      expect(standard.contains(const Offset(54, 58)), isTrue);
      expect(wide.contains(const Offset(54, 58)), isFalse);
      expect(wide.getBounds().width, greaterThan(standard.getBounds().width));
    });

    test('scales with the size', () {
      expect(riftMarkPath(16).getBounds().bottom, closeTo(90 * 0.16, 0.01));
    });
  });
}
