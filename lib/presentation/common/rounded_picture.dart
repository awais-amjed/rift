import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'rounded_square_image.dart';

/// A picture in a rounded square: every avatar and icon picture.
///
/// The corners are cut into the picture's own pixels ([RoundedSquareImage]),
/// and the GPU draws a plain square. On the owner's AMD PC under Linux
/// (Flutter 3.50, Impeller GLES, GNOME on Wayland) every way of having the
/// GPU round a picture failed (Nov 14 2026): a [ClipRRect], and a rounded
/// `DecorationImage`, which clips inside `paintImage`, flickered between
/// square and smooth corners whenever the window redrew; a rounded fill with
/// the picture as its shader stopped flickering but came out stepped, since
/// Impeller smooths the edge of a colour fill there but not of a picture
/// fill. The smoothing comes and goes from frame to frame, so nothing is
/// left to it.
///
/// The picture is decoded at the size it is drawn, as a shader fill tried
/// from Oct 15 to Oct 23 2026 was not, which made it grainy: a full-size
/// picture shrunk to a rail chip skips the smoothing [Image] gets.
///
/// Other rounded pictures (chat attachments, link previews) are still
/// clipped: none was ever seen flickering, and [Image] sizes itself from a
/// picture, which this cannot.
class RoundedPicture extends StatefulWidget {
  final ImageProvider image;
  final double size;
  final double radius;

  /// Drawn until the picture is ready, and instead of it if it fails.
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
  void didUpdateWidget(RoundedPicture old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image ||
        old.size != widget.size ||
        old.radius != widget.radius) {
      _resolve();
    }
  }

  /// Keeps drawing the old picture until the new one is ready, as
  /// `gaplessPlayback` did.
  void _resolve() {
    final stream = RoundedSquareImage(
      widget.image,
      side: widget.size,
      radius: widget.radius,
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
      painter: _SquarePainter(info.image),
    );
  }
}

/// The picture, corners already cut, over the whole box.
class _SquarePainter extends CustomPainter {
  final ui.Image image;

  const _SquarePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_SquarePainter old) => !identical(old.image, image);
}
