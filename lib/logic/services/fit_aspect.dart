import 'dart:ui';

/// The largest box of shape [aspectRatio] (width over height) that fits in
/// [bounds]: full width when the picture is the wider of the two, full height
/// otherwise. How a screen share's box follows its picture.
Size fitAspect(double aspectRatio, Size bounds) {
  if (bounds.width <= 0 || bounds.height <= 0 || aspectRatio <= 0) {
    return Size.zero;
  }
  final heightAtFullWidth = bounds.width / aspectRatio;
  if (heightAtFullWidth <= bounds.height) {
    return Size(bounds.width, heightAtFullWidth);
  }
  return Size(bounds.height * aspectRatio, bounds.height);
}
