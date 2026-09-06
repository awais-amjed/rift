import 'dart:ui';

/// Which drawing of the mark suits a size. See [riftMarkPath].
enum RiftMarkVariant {
  /// 32px and up: the outer silhouette corners carry a 4-unit radius.
  rounded,

  /// 20–31px: the same proportions, fully sharp — sub-pixel radii only
  /// muddy the diagonal.
  sharp,

  /// Under 20px: walls 26 wide and a wider gap, or the gap closes and the
  /// mark becomes a blob. 16px is the floor.
  wide,
}

/// The mark's floor. Below it even the wide variant closes up.
const double riftMarkMinimumSize = 16;

RiftMarkVariant riftMarkVariantFor(double size) {
  if (size >= 32) return RiftMarkVariant.rounded;
  if (size >= 20) return RiftMarkVariant.sharp;
  return RiftMarkVariant.wide;
}

/// Rift's mark — "Canyon": two walls, and the rift is the gap between them.
///
/// Drawn on a 100-unit box and scaled to [size]. Each wall steps inward to a
/// shoulder at mid-height, so the gap opens from the crown, snaps to its
/// narrowest at the shoulder, then widens to the foot; that hard ledge is the
/// fault line, what makes the two sides read as pulled apart rather than
/// placed. The gap is never drawn: it takes the colour of whatever the mark
/// sits on, so the mark is ground-agnostic.
///
/// Only the outer silhouette corners are ever rounded, and only in the
/// [RiftMarkVariant.rounded] drawing, so the crown, waist and foot always
/// measure exactly what the construction says.
Path riftMarkPath(double size, {RiftMarkVariant? variant}) {
  final k = size / 100;
  final path = Path();
  switch (variant ?? riftMarkVariantFor(size)) {
    case RiftMarkVariant.rounded:
      // Left wall: 20 wide, inset 18, r4 on the two outer corners.
      path
        ..moveTo(18 * k, 10 * k)
        ..quadraticBezierTo(18 * k, 6 * k, 22 * k, 6 * k)
        ..lineTo(38 * k, 6 * k)
        ..lineTo(29 * k, 44 * k)
        ..lineTo(43 * k, 44 * k)
        ..lineTo(32 * k, 94 * k)
        ..lineTo(22 * k, 94 * k)
        ..quadraticBezierTo(18 * k, 94 * k, 18 * k, 90 * k)
        ..close()
        // Right wall, mirrored.
        ..moveTo(82 * k, 10 * k)
        ..quadraticBezierTo(82 * k, 6 * k, 78 * k, 6 * k)
        ..lineTo(62 * k, 6 * k)
        ..lineTo(71 * k, 44 * k)
        ..lineTo(57 * k, 44 * k)
        ..lineTo(68 * k, 94 * k)
        ..lineTo(78 * k, 94 * k)
        ..quadraticBezierTo(82 * k, 94 * k, 82 * k, 90 * k)
        ..close();
    case RiftMarkVariant.sharp:
      // Walls 24 wide, gap 28 / 20 / 36.
      path
        ..moveTo(14 * k, 6 * k)
        ..lineTo(38 * k, 6 * k)
        ..lineTo(28 * k, 44 * k)
        ..lineTo(44 * k, 44 * k)
        ..lineTo(32 * k, 94 * k)
        ..lineTo(14 * k, 94 * k)
        ..close()
        ..moveTo(86 * k, 6 * k)
        ..lineTo(62 * k, 6 * k)
        ..lineTo(72 * k, 44 * k)
        ..lineTo(56 * k, 44 * k)
        ..lineTo(68 * k, 94 * k)
        ..lineTo(86 * k, 94 * k)
        ..close();
    case RiftMarkVariant.wide:
      // Walls 26 wide, gap 28 / 22 / 40.
      path
        ..moveTo(10 * k, 6 * k)
        ..lineTo(36 * k, 6 * k)
        ..lineTo(27 * k, 44 * k)
        ..lineTo(39 * k, 44 * k)
        ..lineTo(30 * k, 94 * k)
        ..lineTo(10 * k, 94 * k)
        ..close()
        ..moveTo(90 * k, 6 * k)
        ..lineTo(64 * k, 6 * k)
        ..lineTo(73 * k, 44 * k)
        ..lineTo(61 * k, 44 * k)
        ..lineTo(70 * k, 94 * k)
        ..lineTo(90 * k, 94 * k)
        ..close();
  }
  return path;
}
