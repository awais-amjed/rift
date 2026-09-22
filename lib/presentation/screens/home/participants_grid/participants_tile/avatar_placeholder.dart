import 'package:flutter/material.dart';

import '../../../../common/squircle_avatar.dart';

/// Stands in for a participant who has no camera on.
///
/// The same squircle and identity gradient as everywhere else, just large:
/// a tile with the camera off should still show *who* it is, and the
/// gradient does that faster than an initial on grey.
class AvatarPlaceholder extends StatelessWidget {
  final String name;

  /// The participant's *user* id, so their colour matches their avatar
  /// everywhere else in the app. A LiveKit identity is the wrong thing to pass:
  /// it varies by device and by screenshare, and the gradient would with it.
  final String? seed;

  const AvatarPlaceholder({super.key, required this.name, this.seed});

  static const _maxSize = 96.0;

  @override
  Widget build(BuildContext context) {
    // Centred, with the name badge free to sit over it — its own background
    // keeps it readable. Sized to the tile, though: the row under a screen
    // share is under 100px tall, and a fixed 96 was cut off top and bottom.
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: SquircleAvatar(
          name: name,
          seed: seed,
          size: (constraints.biggest.shortestSide * 0.7).clamp(0.0, _maxSize),
        ),
      ),
    );
  }
}
