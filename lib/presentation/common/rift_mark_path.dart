import 'dart:ui';

/// Which drawing of the mark suits a size. See [riftMarkPath].
enum RiftMarkVariant {
  /// 20px and up: the gap is 7 units wide, as the brand masters draw it.
  standard,

  /// Under 20px: the same two halves, pulled further apart. Seven units of
  /// 100 is under a pixel at 16px, and a gap that lands on one pixel of
  /// half-lit antialiasing is not a gap — the halves fuse into a disc.
  wide,
}

/// The mark's floor. Below it even the wide variant closes up.
const double riftMarkMinimumSize = 16;

RiftMarkVariant riftMarkVariantFor(double size) =>
    size >= 20 ? RiftMarkVariant.standard : RiftMarkVariant.wide;

/// Rift's mark: two half-discs pulled apart, and the rift is the gap.
///
/// Drawn on a 100-unit box and scaled to [size]. One disc of radius 32 cut
/// down its diameter, the halves slid apart across the cut and past each
/// other along it, so the flat edges face each other over the gap and the
/// round backs face out. They share a centre of rotation at (50, 50): the
/// figure is unchanged by a half turn, which is what makes two halves of one
/// thing read as two halves of one thing rather than as two shapes.
///
/// The gap is never drawn. It takes the colour of whatever the mark sits on,
/// so the mark is ground-agnostic — the reason there is no tile around it
/// anywhere inside the app.
Path riftMarkPath(double size, {RiftMarkVariant? variant}) {
  final k = size / 100;
  final gap = switch (variant ?? riftMarkVariantFor(size)) {
    RiftMarkVariant.standard => _gap,
    RiftMarkVariant.wide => _gapWide,
  };

  // Widening the gap moves the two flat edges apart and nothing else: the
  // radius, the vertical offset and the centre of rotation all hold, so the
  // small drawing is the same figure rather than a second one.
  final leftEdge = (50 - gap / 2) * k;
  final rightEdge = (50 + gap / 2) * k;
  final radius = Radius.circular(_radius * k);

  return Path()
    ..moveTo(leftEdge, (_upper - _radius) * k)
    ..arcToPoint(
      Offset(leftEdge, (_upper + _radius) * k),
      radius: radius,
      clockwise: false,
    )
    ..close()
    ..moveTo(rightEdge, (_lower - _radius) * k)
    ..arcToPoint(
      Offset(rightEdge, (_lower + _radius) * k),
      radius: radius,
      clockwise: true,
    )
    ..close();
}

const double _radius = 32;

/// The two centres, 16 apart either side of the middle. The mark therefore
/// stands 10 to 90 whatever the gap is, so a widened drawing still fills the
/// box it is handed.
const double _upper = 42;
const double _lower = 58;

const double _gap = 7;
const double _gapWide = 12;
