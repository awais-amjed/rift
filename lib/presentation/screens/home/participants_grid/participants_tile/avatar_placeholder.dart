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

  /// The strip the name badge takes at the tile's foot: its 12px inset and
  /// its own height, with a little air.
  static const _badgeBand = 46.0;

  static const _maxSize = 96.0;

  /// Smaller than this and the badge says who it is better than a sliver of
  /// gradient would.
  static const _minSize = 24.0;

  @override
  Widget build(BuildContext context) {
    // Sized to the tile, and lifted clear of the name badge when centring
    // would put the two on top of each other. The row under a screen share is
    // under 100px tall, and a fixed 96 was cut off top and bottom there, with
    // the badge over what was left.
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        var size = (constraints.biggest.shortestSide * 0.6).clamp(
          0.0,
          _maxSize,
        );
        final clearsBadge = height / 2 + size / 2 <= height - _badgeBand;
        if (clearsBadge) {
          return Center(
            child: SquircleAvatar(name: name, seed: seed, size: size),
          );
        }
        size = size.clamp(0.0, height - _badgeBand - 8);
        if (size < _minSize) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: _badgeBand),
          child: Center(
            child: SquircleAvatar(name: name, seed: seed, size: size),
          ),
        );
      },
    );
  }
}
