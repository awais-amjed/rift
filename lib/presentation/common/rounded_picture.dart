import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// A picture filling a rounded square: every avatar and icon picture.
///
/// Painted as the fill of the shape, the way an initial's gradient is, with
/// no clip anywhere. On the owner's AMD PC under Linux (Flutter 3.50,
/// Impeller GLES, GNOME on Wayland) a rounded picture flickered between
/// square and rounded corners on every frame, whether it was cut by a
/// [ClipRRect] or drawn as a rounded `DecorationImage`, which clips inside
/// `paintImage` (Nov 14 2026). The initials beside them, rounded fills,
/// never did.
///
/// This was tried from Oct 15 to Oct 23 2026 and undone because the
/// pictures came out grainy: a full-size picture shrunk to a rail chip in
/// the shader skips the smoothing [Image] gets. So the picture is decoded at
/// the size it is drawn ([coverDecodeSize]), and the shader has nothing left
/// to shrink.
///
/// Other rounded pictures (chat attachments, link previews) are still
/// clipped: none was ever seen flickering, and [Image] sizes itself from a
/// picture, which this cannot.
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

  /// The size to decode a [width] by [height] picture at, so that covering a
  /// square [side] pixels across needs no shrinking: its shorter side
  /// becomes [side]. Null leaves a picture that small at its own size.
  @visibleForTesting
  static ui.TargetImageSize? coverDecodeSize(int width, int height, int side) {
    final shorter = math.min(width, height);
    if (shorter <= side) return null;
    final scale = side / shorter;
    return ui.TargetImageSize(
      width: math.max(side, (width * scale).round()),
      height: math.max(side, (height * scale).round()),
    );
  }

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
  void didUpdateWidget(RoundedPicture old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image || old.size != widget.size) _resolve();
  }

  /// Keeps drawing the old picture until the new one is decoded, as
  /// `gaplessPlayback` did.
  void _resolve() {
    final stream = _CoverSquare(
      widget.image,
      widget.size,
    ).resolve(createLocalImageConfiguration(context));
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

// ── Decoding at the drawn size ──────────────────────────

/// [inner], decoded so it covers a square [side] logical pixels across with
/// no shrinking ([RoundedPicture.coverDecodeSize]). Unlike [ResizeImage],
/// which can only fit a picture inside a box, so a wide one would come out
/// shorter than the square and be stretched back up. Cached per picture and
/// size like any other image.
@immutable
class _CoverSquare extends ImageProvider<_CoverKey> {
  final ImageProvider inner;
  final double side;

  const _CoverSquare(this.inner, this.side);

  @override
  Future<_CoverKey> obtainKey(ImageConfiguration configuration) {
    final pixels = (side * (configuration.devicePixelRatio ?? 1)).ceil();
    // Stays synchronous when the inner key is, so a cached picture draws in
    // the same frame.
    return inner.obtainKey(configuration).then((key) => _CoverKey(key, pixels));
  }

  @override
  ImageStreamCompleter loadImage(_CoverKey key, ImageDecoderCallback decode) {
    // ignore: invalid_use_of_protected_member
    return inner.loadImage(
      key.inner,
      (buffer, {getTargetSize}) => decode(
        buffer,
        getTargetSize: (width, height) =>
            RoundedPicture.coverDecodeSize(width, height, key.pixels) ??
            const ui.TargetImageSize(),
      ),
    );
  }
}

@immutable
class _CoverKey {
  final Object inner;
  final int pixels;

  const _CoverKey(this.inner, this.pixels);

  @override
  bool operator ==(Object other) =>
      other is _CoverKey && other.inner == inner && other.pixels == pixels;

  @override
  int get hashCode => Object.hash(inner, pixels);
}
