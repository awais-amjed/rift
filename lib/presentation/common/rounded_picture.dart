import 'package:flutter/material.dart';

/// A picture cut to a rounded square: every avatar and icon picture.
///
/// A plain [ClipRRect] round an [Image], which leaves the scaling to Flutter
/// (mipmapped, so a large picture shrunk to a rail chip stays smooth).
/// From Oct 15 to Oct 23 2026 the picture was painted by hand as the fill of
/// the shape instead, after picture avatars flickered square on an AMD PC
/// under Linux, and its pictures came out grainy and its corners stepped.
/// Both trace to Flutter 3.47's Impeller on Linux, which has no working MSAA
/// (flutter/flutter#191171): a clip's edge, a stroke and a path go
/// unsmoothed, and only a filled primitive is. Fixed upstream by #191379,
/// which no stable release has yet. Until one does, these corners are
/// stepped on Linux like every other clip in the app, and smooth elsewhere.
class RoundedPicture extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final placeholder = fallback ?? SizedBox.square(dimension: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image(
        image: image,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        // Keeps the old picture until the new one is decoded.
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            frame == null && !wasSynchronouslyLoaded ? placeholder : child,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}
