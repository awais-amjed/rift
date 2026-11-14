import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// [inner] as a square [side] logical pixels across, covering it the way
/// `BoxFit.cover` does, with its corners of [radius] already cut into its
/// pixels: drawn as a plain square, it comes out rounded and smooth.
///
/// What [RoundedPicture] draws. The GPU rounds nothing, so there is no edge
/// for it to smooth one frame and not the next, which is what made avatars
/// flicker on an AMD PC under Linux (see [RoundedPicture]). The picture is
/// decoded at the size it is drawn ([coverDecodeSize]), cut to a square, and
/// each corner pixel kept by how much of it lies inside the curve
/// ([coverage]). Only the first frame of an animated picture is kept.
/// Cached per picture, size and radius like any other image.
@immutable
class RoundedSquareImage extends ImageProvider<RoundedSquareKey> {
  final ImageProvider inner;
  final double side;
  final double radius;

  const RoundedSquareImage(
    this.inner, {
    required this.side,
    required this.radius,
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

  /// How much of the pixel centred on ([x], [y]) lies inside a square [side]
  /// pixels across with corners of [radius]: 1 inside, 0 outside, and in
  /// between along the curve, by the centre's distance from it.
  @visibleForTesting
  static double coverage(double x, double y, int side, double radius) {
    final r = math.min(radius, side / 2);
    final qx = math.max(r - x, x - (side - r));
    final qy = math.max(r - y, y - (side - r));
    if (qx <= 0 || qy <= 0) return 1;
    final distance = math.sqrt(qx * qx + qy * qy);
    return (r - distance + 0.5).clamp(0.0, 1.0);
  }

  /// Fades each corner pixel of a [side] by [side] picture in premultiplied
  /// RGBA by its [coverage], all four channels alike so it stays
  /// premultiplied.
  @visibleForTesting
  static void cutCorners(Uint8List rgba, int side, double radius) {
    final band = math.min(radius, side / 2).ceil();
    if (band <= 0) return;
    for (var y = 0; y < side; y++) {
      if (y >= band && y < side - band) continue;
      for (var x = 0; x < side; x++) {
        if (x >= band && x < side - band) continue;
        final keep = coverage(x + 0.5, y + 0.5, side, radius);
        if (keep >= 1) continue;
        final at = (y * side + x) * 4;
        for (var i = at; i < at + 4; i++) {
          rgba[i] = (rgba[i] * keep).round();
        }
      }
    }
  }

  @override
  Future<RoundedSquareKey> obtainKey(ImageConfiguration configuration) {
    final pixels = math.max(
      1,
      (side * (configuration.devicePixelRatio ?? 1)).ceil(),
    );
    final radiusPixels = side > 0 ? radius * pixels / side : 0.0;
    // Stays synchronous when the inner key is, so a cached picture draws in
    // the same frame.
    return inner
        .obtainKey(configuration)
        .then((key) => RoundedSquareKey(key, pixels, radiusPixels));
  }

  @override
  ImageStreamCompleter loadImage(
    RoundedSquareKey key,
    ImageDecoderCallback decode,
  ) {
    // ignore: invalid_use_of_protected_member
    final decoded = inner.loadImage(
      key.inner,
      (buffer, {getTargetSize}) => decode(
        buffer,
        getTargetSize: (width, height) =>
            coverDecodeSize(width, height, key.pixels) ??
            const ui.TargetImageSize(),
      ),
    );
    return OneFrameImageStreamCompleter(
      _firstFrame(decoded).then((image) => _round(image, key)),
    );
  }

  static Future<ui.Image> _firstFrame(ImageStreamCompleter source) {
    final done = Completer<ui.Image>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        source.removeListener(listener);
        if (done.isCompleted) return info.dispose();
        done.complete(info.image);
      },
      onError: (error, stack) {
        source.removeListener(listener);
        if (!done.isCompleted) done.completeError(error, stack);
      },
    );
    source.addListener(listener);
    return done.future;
  }

  static Future<ImageInfo> _round(
    ui.Image decoded,
    RoundedSquareKey key,
  ) async {
    final side = key.pixels;
    try {
      // The centred square, scaled to the side: one to one for a picture
      // decoded larger, which is nearly every one.
      final shorter = math.min(decoded.width, decoded.height).toDouble();
      final from = Rect.fromLTWH(
        ((decoded.width - shorter) / 2).floorToDouble(),
        ((decoded.height - shorter) / 2).floorToDouble(),
        shorter,
        shorter,
      );
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        decoded,
        from,
        Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      final square = await picture.toImage(side, side);
      picture.dispose();
      final data = await square.toByteData(); // premultiplied RGBA
      square.dispose();
      final rgba = data!.buffer.asUint8List();
      cutCorners(rgba, side, key.radius);
      return ImageInfo(image: await _fromPixels(rgba, side));
    } finally {
      decoded.dispose();
    }
  }

  static Future<ui.Image> _fromPixels(Uint8List rgba, int side) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: side,
      height: side,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }
}

@immutable
class RoundedSquareKey {
  final Object inner;
  final int pixels;
  final double radius;

  const RoundedSquareKey(this.inner, this.pixels, this.radius);

  @override
  bool operator ==(Object other) =>
      other is RoundedSquareKey &&
      other.inner == inner &&
      other.pixels == pixels &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(inner, pixels, radius);
}
