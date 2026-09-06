import 'package:flutter_test/flutter_test.dart';
import 'package:rift/presentation/common/rift_mark_path.dart';

void main() {
  group('riftMarkVariantFor', () {
    test('rounds the silhouette only where the radius survives', () {
      expect(riftMarkVariantFor(76), RiftMarkVariant.rounded);
      expect(riftMarkVariantFor(32), RiftMarkVariant.rounded);
      expect(riftMarkVariantFor(31), RiftMarkVariant.sharp);
      expect(riftMarkVariantFor(24), RiftMarkVariant.sharp);
      expect(riftMarkVariantFor(19), RiftMarkVariant.wide);
      expect(riftMarkVariantFor(16), RiftMarkVariant.wide);
    });
  });

  group('riftMarkPath', () {
    test('fills the box top to bottom, inset from the sides', () {
      for (final variant in RiftMarkVariant.values) {
        final bounds = riftMarkPath(100, variant: variant).getBounds();
        expect(bounds.top, 6, reason: '$variant crown');
        expect(bounds.bottom, 94, reason: '$variant foot');
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
        for (final y in [8.0, 30.0, 44.0, 50.0, 70.0, 92.0]) {
          expect(
            path.contains(Offset(50, y)),
            isFalse,
            reason: '$variant at y=$y',
          );
        }
        expect(
          path.contains(const Offset(28, 20)),
          isTrue,
          reason: '$variant left wall',
        );
        expect(
          path.contains(const Offset(72, 80)),
          isTrue,
          reason: '$variant right wall',
        );
      }
    });

    test('scales with the size', () {
      expect(riftMarkPath(16).getBounds().bottom, closeTo(94 * 0.16, 0.01));
    });
  });
}
