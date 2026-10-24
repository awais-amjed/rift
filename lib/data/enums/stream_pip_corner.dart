/// Which corner of a watched stream the sharer's camera floats in
/// (`StreamCameraPip`). Bottom right by default, where a film's picture in
/// picture usually is; the viewer drags it to another when it covers
/// something.
enum StreamPipCorner {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  bool get isTop => this == topLeft || this == topRight;
  bool get isLeft => this == topLeft || this == bottomLeft;

  /// The corner nearest the point ([x], [y]) on a stage [width] by
  /// [height]: the quarter it is in.
  static StreamPipCorner nearest(
    double x,
    double y,
    double width,
    double height,
  ) {
    final left = x < width / 2;
    final top = y < height / 2;
    if (top) return left ? topLeft : topRight;
    return left ? bottomLeft : bottomRight;
  }
}
