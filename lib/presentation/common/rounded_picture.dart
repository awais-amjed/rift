import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A picture filling a rounded square, painted as the fill of the shape
/// rather than cut out of a square by a clip.
///
/// On Linux, Impeller draws a rounded fill's edge in its shader, but a
/// rounded clip goes through the depth buffer, and on some drivers (seen
/// on an AMD card under GNOME) that clip came and went between frames: picture
/// avatars flickered between square and rounded while the gradient avatars
/// beside them, which are fills, never did. So a picture avatar is drawn the
/// same way as a gradient one.
class RoundedPicture extends StatefulWidget {
  final ImageProvider image;
  final double size;
  final double radius;

  /// Drawn until the picture is decoded, and instead of it if it fails.
  final Widget? fallback;

  const RoundedPicture({
    super.key,
    required this.image,
    required this.size,
    required this.radius,
    this.fallback,
  });

  @override
  State<RoundedPicture> createState() => _RoundedPictureState();
}

class _RoundedPictureState extends State<RoundedPicture> {
  ImageStream? _stream;
  ImageInfo? _info;
  bool _failed = false;
  late final _listener = ImageStreamListener(_onImage, onError: _onError);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(RoundedPicture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _resolve();
  }

  /// Keeps drawing the old picture until the new one is decoded, as
  /// `gaplessPlayback` did.
  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool _) {
    setState(() {
      _info?.dispose();
      _info = info;
      _failed = false;
    });
  }

  void _onError(Object _, StackTrace? _) {
    setState(() {
      _info?.dispose();
      _info = null;
      _failed = true;
    });
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null || _failed) {
      return widget.fallback ?? SizedBox.square(dimension: widget.size);
    }
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _RoundedPicturePainter(info.image, widget.radius),
    );
  }
}

class _RoundedPicturePainter extends CustomPainter {
  final ui.Image image;
  final double radius;

  const _RoundedPicturePainter(this.image, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    // BoxFit.cover: scaled to fill the square, centred, the overflow cut.
    final scale = math.max(
      size.width / image.width,
      size.height / image.height,
    );
    final dx = (size.width - image.width * scale) / 2;
    final dy = (size.height - image.height * scale) / 2;
    final matrix = Float64List.fromList([
      scale, 0, 0, 0, //
      0, scale, 0, 0, //
      0, 0, 1, 0, //
      dx, dy, 0, 1, //
    ]);
    final paint = Paint()
      ..shader = ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        matrix,
        filterQuality: FilterQuality.medium,
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RoundedPicturePainter old) =>
      !identical(old.image, image) || old.radius != radius;
}
